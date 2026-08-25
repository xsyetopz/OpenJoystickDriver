import Foundation

let gipReadPacketLength = 64
let gipReadTimeoutMs: UInt32 = 100
let usbOpenRetryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
let keepAliveIntervalNs: UInt64 = 4_000_000_000
/// Target input loop cadence in nanoseconds.
///
/// Defensive pacing prevents a transport that completes timeouts immediately from
/// creating a hot loop that can trigger launchd "inefficient" kills.
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
  private let packetLog: PacketLogBuffer

  init(inputState: DeviceInputState, maxPacketLogEntries: Int) {
    self.inputState = inputState
    self.packetLog = PacketLogBuffer(maxEntries: maxPacketLogEntries)
  }

  func updateInputState(_ state: DeviceInputState) { lock.withLock { inputState = state } }

  func currentInputState() -> DeviceInputState { lock.withLock { inputState } }

  func appendPacket(bytes: [UInt8], direction: String) {
    packetLog.append(bytes: bytes, direction: direction)
  }

  func currentPacketLog() -> [PacketLogEntry] { packetLog.entries() }
}

/// Manages full lifecycle of single connected controller.
/// Each controller gets its own DevicePipeline actor - one
/// failure never affects others.
actor DevicePipeline {
  enum Transport {
    /// Vendor-specific interface owned by the selected Apple USB transport backend.
    case usb(device: USBTransportDevice)
    /// Class 0x03 via IOKit
    case hid(locationID: UInt32)
  }

  let identifier: DeviceIdentifier
  let transport: Transport
  let parser: any InputParser
  let dispatcher: any OutputDispatcher
  let usbTransportProvider: (any USBTransportProvider)?
  let transportProfile: DeviceTransportProfile
  let idleMonitorIntervalNanoseconds: UInt64
  var isActive = false
  var usbHandle: (any USBTransportSession)?
  var currentInputState: DeviceInputState
  var outputState: DeviceInputState
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
    usbTransportProvider: (any USBTransportProvider)? = nil,
    transportProfile: DeviceTransportProfile = .gipDefault,
    externalOutputAllowed: Bool = true,
    idleTimeoutNanoseconds: UInt64 = defaultControllerIdleTimeoutNanoseconds,
    idleMonitorIntervalNanoseconds: UInt64 = defaultIdleMonitorIntervalNanoseconds
  ) {
    self.identifier = identifier
    self.transport = transport
    self.parser = parser
    self.dispatcher = dispatcher
    self.usbTransportProvider = usbTransportProvider
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
    case .usb(let device): await startUSBPipeline(device: device)
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
      await handle.close()
      usbHandle = nil
    }
    print("[DevicePipeline] Stopped: \(identifier)")
  }

  /// Feed HID input report data (called by DeviceManager for class 0x03 devices).
  @discardableResult func feedHIDData(_ data: Data) async -> [PhysicalHIDOutputReport] {
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

  /// Feed one descriptor-decoded value to the Generic HID fallback.
  func feedHIDElementValue(_ value: HIDElementValue) async {
    guard isActive, inputConnectionActive, let elementParser = parser as? any HIDElementValueParser
    else { return }
    let events = elementParser.parse(elementValue: value)
    await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
  }

  nonisolated func requiresInputConnectionBeforeOutput() -> Bool {
    (parser as? any ControllerInputConnectionLifecycle)?.requiresInputConnectionBeforeOutput
      ?? false
  }

  func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport] {
    if requiresInputConnectionBeforeOutput(), !inputConnectionActive { return [] }
    return (parser as? any HIDShutdownFeatureReportProvider)?.hidShutdownFeatureReports() ?? []
  }

  nonisolated func physicalOutputCapabilities() -> PhysicalControllerOutputCapabilities {
    let rumbleMotors: [PhysicalRumbleMotor]
    if let usbOutput = parser as? PhysicalRumbleOutput {
      rumbleMotors = usbOutput.physicalRumbleMotors
    } else if let hidOutput = parser as? PhysicalHIDRumbleOutput {
      rumbleMotors = hidOutput.physicalRumbleMotors
    } else if let featureHaptics = parser as? PhysicalHIDFeatureHapticOutput {
      rumbleMotors = featureHaptics.physicalRumbleMotors
    } else {
      rumbleMotors = []
    }
    let binaryRumbleMotors = (parser as? PhysicalHIDRumbleOutput)?.physicalBinaryRumbleMotors ?? []
    var lighting: [PhysicalLightingFeature] = []
    lighting += (parser as? PhysicalPlayerIndicatorOutput)?.physicalLightingFeatures ?? []
    lighting += (parser as? PhysicalHIDPlayerIndicatorOutput)?.physicalLightingFeatures ?? []
    lighting += (parser as? PhysicalHIDColorOutput)?.physicalLightingFeatures ?? []
    lighting += (parser as? PhysicalHIDFeatureBrightnessOutput)?.physicalLightingFeatures ?? []
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: rumbleMotors,
      lightingFeatures: lighting,
      binaryRumbleMotors: binaryRumbleMotors
    )
  }

  nonisolated func supportsPhysicalRumble() -> Bool { physicalOutputCapabilities().supportsRumble }

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
      print("[DevicePipeline] Output ungated by foreground consumer: \(identifier)")
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

  func updateOutputState(from events: [ControllerEvent]) { outputState.apply(events: events) }

  func neutralizeOutput() async {
    let neutralizingEvents = outputState.neutralizingEvents()
    guard !neutralizingEvents.isEmpty else { return }
    await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
    updateOutputState(from: neutralizingEvents)
  }

  func handleInputConnectionStateChangeIfNeeded() async -> [PhysicalHIDOutputReport] {
    guard let lifecycle = parser as? any ControllerInputConnectionLifecycle,
      let state = lifecycle.consumeInputConnectionStateChange()
    else { return [] }

    if let output = parser as? any USBInputConnectionOutputProvider, let handle = usbHandle {
      for packet in output.usbInputConnectionOutputPackets(for: state) {
        do {
          _ = try await handle.writeInterruptPacket(
            endpoint: transportProfile.outputEndpoint,
            data: packet,
            timeout: 2_000
          )
          appendToPacketLog(bytes: packet, direction: "tx")
        } catch {
          print("[DevicePipeline] USB lifecycle output failed for \(identifier): \(error)")
        }
      }
    }

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
    snapshots.appendPacket(bytes: bytes, direction: direction)
  }

  // MARK: - Rumble

  func sendRumble(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) async -> Bool {
    guard let handle = usbHandle, let rumbleOutput = parser as? PhysicalRumbleOutput else {
      return false
    }
    do {
      try await rumbleOutput.sendPhysicalRumble(
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

  func hidFeatureHapticReports(left: UInt8, right: UInt8, durationMs: Int)
    -> [PhysicalHIDOutputReport]
  {
    (parser as? PhysicalHIDFeatureHapticOutput)?.physicalHapticReports(
      left: left,
      right: right,
      durationMs: durationMs
    ) ?? []
  }

  nonisolated func minimumPhysicalOutputIntervalNanoseconds() -> UInt64 {
    (parser as? PhysicalHIDRumbleOutput)?.minimumPhysicalOutputIntervalNanoseconds ?? 0
  }

  func hidRumbleReport(left: UInt8, right: UInt8, lt: UInt8, rt: UInt8) -> PhysicalHIDOutputReport?
  {
    guard let rumbleOutput = parser as? PhysicalHIDRumbleOutput else { return nil }
    return rumbleOutput.physicalRumbleReport(left: left, right: right, lt: lt, rt: rt)
  }

  func hidColorReport(red: UInt8, green: UInt8, blue: UInt8) -> PhysicalHIDOutputReport? {
    (parser as? PhysicalHIDColorOutput)?.physicalColorReport(red: red, green: green, blue: blue)
  }

  func hidBrightnessReport(_ brightness: UInt8) -> PhysicalHIDOutputReport? {
    (parser as? PhysicalHIDFeatureBrightnessOutput)?.physicalBrightnessReport(brightness)
  }

  func hidPlayerIndicatorReport(_ indicator: PhysicalPlayerIndicator) -> PhysicalHIDOutputReport? {
    (parser as? PhysicalHIDPlayerIndicatorOutput)?.physicalPlayerIndicatorReport(indicator)
  }

  func sendPlayerIndicator(_ indicator: PhysicalPlayerIndicator) async -> Bool {
    guard let handle = usbHandle, let lightingOutput = parser as? PhysicalPlayerIndicatorOutput
    else { return false }
    do {
      try await lightingOutput.sendPhysicalPlayerIndicator(handle: handle, indicator: indicator)
      return true
    } catch {
      print("[DevicePipeline] Player indicator send failed for \(identifier): \(error)")
      return false
    }
  }
}
