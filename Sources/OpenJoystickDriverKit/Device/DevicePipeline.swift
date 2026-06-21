import Foundation
import SwiftUSB

let gipReadPacketLength = 64
let gipReadTimeoutMs: UInt32 = 100
let usbOpenRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
let keepAliveIntervalNs: UInt64 = 4_000_000_000
/// Target input loop cadence in nanoseconds.
///
/// If libusb returns timeouts immediately (instead of waiting for timeout),
/// this prevents a hot loop that can trigger launchd "inefficient" kills.
let usbIdleLoopCadenceNs: UInt64 = UInt64(gipReadTimeoutMs) * 1_000_000
let usbIOErrorReconnectThreshold = 10
let usbIOErrorBackoffBaseNs: UInt64 = 250_000_000  // 250ms
let usbIOErrorBackoffMaxNs: UInt64 = 2_000_000_000  // 2s
let usbIOErrorLogIntervalNs: UInt64 = 5_000_000_000  // 5s
private let defaultControllerIdleTimeoutNanoseconds: UInt64 = 30_000_000_000
private let defaultIdleMonitorIntervalNanoseconds: UInt64 = 1_000_000_000

private final class DevicePipelineSnapshots: @unchecked Sendable {
  private let lock = NSLock()
  private var inputState: DeviceInputState
  var packetLog: [PacketLogEntry] = []
  let maxPacketLogEntries: Int

  init(inputState: DeviceInputState, maxPacketLogEntries: Int) {
    self.inputState = inputState
    self.maxPacketLogEntries = maxPacketLogEntries
  }

  func updateInputState(_ state: DeviceInputState) {
    lock.withLock { inputState = state }
  }

  func currentInputState() -> DeviceInputState {
    lock.withLock { inputState }
  }

  func appendPacket(_ entry: PacketLogEntry) {
    lock.withLock {
      packetLog.append(entry)
      if packetLog.count > maxPacketLogEntries {
        packetLog.removeFirst(packetLog.count - maxPacketLogEntries)
      }
    }
  }

  func currentPacketLog() -> [PacketLogEntry] {
    lock.withLock { packetLog }
  }
}

/// Manages full lifecycle of single connected controller.
/// Each controller gets its own DevicePipeline actor - one
/// failure never affects others.
actor DevicePipeline {
  enum Transport {
    /// Class 0xFF via SwiftUSB
    case usb(vendorID: UInt16, productID: UInt16)
    /// Class 0x03 via IOKit
    case hid(locationID: UInt32)
  }

  let identifier: DeviceIdentifier
  let transport: Transport
  let parser: any InputParser
  let dispatcher: any OutputDispatcher
  let usbContext: USBContext?
  let transportProfile: DeviceTransportProfile
  let idleMonitorIntervalNanoseconds: UInt64
  var isActive = false
  var usbHandle: USBDeviceHandle?
  var currentInputState: DeviceInputState
  var outputState: DeviceInputState
  var packetLog: [PacketLogEntry] = []
  let maxPacketLogEntries = 200
  private let snapshots: DevicePipelineSnapshots
  var sleepGate = ControllerSleepGate()
  var idleMonitorTask: Task<Void, Never>?
  var externalOutputAllowed: Bool
  var waitingForExternalNeutral = false
  var consecutiveUSBIOErrors: Int = 0
  var lastUSBIOErrorLogNs: UInt64 = 0
  var inputConnectionActive: Bool

  init(
    identifier: DeviceIdentifier,
    transport: Transport,
    parser: any InputParser,
    dispatcher: any OutputDispatcher,
    usbContext: USBContext?,
    transportProfile: DeviceTransportProfile = .gipDefault,
    externalOutputAllowed: Bool = true,
    idleTimeoutNanoseconds: UInt64 = defaultControllerIdleTimeoutNanoseconds,
    idleMonitorIntervalNanoseconds: UInt64 = defaultIdleMonitorIntervalNanoseconds
  ) {
    self.identifier = identifier
    self.transport = transport
    self.parser = parser
    self.dispatcher = dispatcher
    self.usbContext = usbContext
    self.transportProfile = transportProfile
    self.idleMonitorIntervalNanoseconds = idleMonitorIntervalNanoseconds
    self.externalOutputAllowed = externalOutputAllowed
    let inputLifecycle = parser as? any ControllerInputConnectionLifecycle
    self.inputConnectionActive = !(inputLifecycle?.requiresInputConnectionBeforeOutput ?? false)
    let initialState = DeviceInputState(
      vendorID: identifier.vendorID,
      productID: identifier.productID
    )
    self.currentInputState = initialState
    self.outputState = initialState
    self.snapshots = DevicePipelineSnapshots(
      inputState: initialState,
      maxPacketLogEntries: maxPacketLogEntries
    )
    self.sleepGate = ControllerSleepGate(idleTimeoutNanoseconds: idleTimeoutNanoseconds)
  }

  /// Start pipeline: open device, handshake, begin input loop.
  func start() async {
    guard !isActive else { return }
    isActive = true
    startIdleMonitor()

    switch transport {
    case .usb(let vid, let pid): await startUSBPipeline(vendorID: vid, productID: pid)
    case .hid:
      // HID pipeline: data fed via feedHIDData(); no separate startup loop needed
      print("[DevicePipeline] HID pipeline ready" + " for \(identifier)")
    }
  }

  /// Stop pipeline and clean up resources.
  func stop() async {
    isActive = false
    idleMonitorTask?.cancel()
    idleMonitorTask = nil
    await neutralizeOutput()
    if let listener = dispatcher as? any ControllerLifecycleListener {
      listener.controllerDidStop(identifier)
    }
    if let handle = usbHandle {
      try? handle.releaseInterface(0)
      usbHandle = nil
    }
    print("[DevicePipeline] Stopped: \(identifier)")
  }

  /// Feed HID input report data (called by DeviceManager for class 0x03 devices).
  @discardableResult
  func feedHIDData(_ data: Data) async -> [PhysicalHIDOutputReport] {
    guard isActive else { return [] }
    appendToPacketLog(bytes: Array(data), direction: "rx")
    do {
      let events = try parser.parse(data: data)
      let featureReports = await handleInputConnectionStateChangeIfNeeded()
      guard inputConnectionActive else { return featureReports }
      await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
      return featureReports
    } catch {
      print("[DevicePipeline] Parse error" + " for \(identifier): \(error)")
      return []
    }
  }

  nonisolated func requiresInputConnectionBeforeOutput() -> Bool {
    (parser as? any ControllerInputConnectionLifecycle)?
      .requiresInputConnectionBeforeOutput ?? false
  }

  func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport] {
    if requiresInputConnectionBeforeOutput(), !inputConnectionActive { return [] }
    return (parser as? any HIDShutdownFeatureReportProvider)?.hidShutdownFeatureReports() ?? []
  }

  nonisolated func supportsPhysicalRumble() -> Bool {
    if let usbOutput = parser as? PhysicalRumbleOutput {
      return usbOutput.supportsPhysicalRumble
    }
    if let hidOutput = parser as? PhysicalHIDRumbleOutput {
      return hidOutput.supportsPhysicalRumble
    }
    return false
  }

  // MARK: - Input state and packet log

  nonisolated func inputState() -> DeviceInputState { snapshots.currentInputState() }
  nonisolated func getPacketLog() -> [PacketLogEntry] { snapshots.currentPacketLog() }

  func setExternalOutputAllowed(_ allowed: Bool) async {
    let changed = externalOutputAllowed != allowed
    guard changed else { return }
    externalOutputAllowed = allowed

    if !allowed {
      waitingForExternalNeutral = false
      let neutralizingEvents = outputState.neutralizingEvents()
      if !neutralizingEvents.isEmpty {
        await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
        updateOutputState(from: neutralizingEvents)
      }
      print("[DevicePipeline] Output gated by foreground consumer: \(identifier)")
      return
    }

    let shouldWaitForNeutral = !currentInputState.isEffectivelyNeutral
    waitingForExternalNeutral = shouldWaitForNeutral

    if shouldWaitForNeutral {
      print(
        "[DevicePipeline] Foreground gate lifted; suppressing hidden "
          + "non-neutral state: \(identifier)"
      )
    } else {
      print(
        "[DevicePipeline] Output ungated by foreground consumer: \(identifier)"
      )
    }
  }

  func updateObservedInputState(from events: [ControllerEvent]) {
    currentInputState.apply(events: events)
    snapshots.updateInputState(currentInputState)
  }

  private func resetObservedInputState() {
    currentInputState = DeviceInputState(
      vendorID: identifier.vendorID,
      productID: identifier.productID
    )
    snapshots.updateInputState(currentInputState)
  }

  func updateOutputState(from events: [ControllerEvent]) {
    outputState.apply(events: events)
  }

  func neutralizeOutput() async {
    let neutralizingEvents = outputState.neutralizingEvents()
    guard !neutralizingEvents.isEmpty else { return }
    await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
    updateOutputState(from: neutralizingEvents)
  }

  private func handleInputConnectionStateChangeIfNeeded() async -> [PhysicalHIDOutputReport] {
    guard let lifecycle = parser as? any ControllerInputConnectionLifecycle,
      let state = lifecycle.consumeInputConnectionStateChange()
    else { return [] }

    switch state {
    case .connected:
      guard !inputConnectionActive else { return [] }
      inputConnectionActive = true
      await dispatcher.dispatch(events: [], from: identifier)
      print("[DevicePipeline] Input controller connected: \(identifier)")
      return (parser as? any HIDStartupFeatureReportProvider)?.hidStartupFeatureReports() ?? []
    case .disconnected:
      resetObservedInputState()
      await neutralizeOutput()
      if inputConnectionActive, let listener = dispatcher as? any ControllerLifecycleListener {
        listener.controllerDidStop(identifier)
      }
      inputConnectionActive = false
      waitingForExternalNeutral = false
      print("[DevicePipeline] Input controller disconnected: \(identifier)")
      return (parser as? any HIDShutdownFeatureReportProvider)?.hidShutdownFeatureReports() ?? []
    }
  }

  func appendToPacketLog(bytes: [UInt8], direction: String) {
    let hexString = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    let entry = PacketLogEntry(
      timestamp: Date().timeIntervalSince1970,
      direction: direction,
      hex: hexString,
      length: bytes.count
    )
    packetLog.append(entry)
    if packetLog.count > maxPacketLogEntries {
      packetLog.removeFirst(packetLog.count - maxPacketLogEntries)
    }
    snapshots.appendPacket(entry)
  }

  // MARK: - Rumble

  func sendRumble(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) -> Bool {
    guard let handle = usbHandle, let rumbleOutput = parser as? PhysicalRumbleOutput else {
      return false
    }
    do {
      try rumbleOutput.sendPhysicalRumble(
        handle: handle,
        left: left,
        right: right,
        lt: lt,
        rt: rt
      )
      return true
    } catch {
      print("[DevicePipeline] Rumble send failed for \(identifier): \(error)")
      return false
    }
  }

  func hidRumbleReport(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8)
    -> PhysicalHIDOutputReport?
  {
    guard let rumbleOutput = parser as? PhysicalHIDRumbleOutput else { return nil }
    return rumbleOutput.physicalRumbleReport(left: left, right: right, lt: lt, rt: rt)
  }

}
