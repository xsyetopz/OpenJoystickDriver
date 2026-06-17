import Foundation
import SwiftUSB

let usbDetectionPollNanoseconds: UInt64 = 2_000_000_000
let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000
let usbVendorSpecificClass: UInt8 = 0xFF

/// Manages device detection and pipeline lifecycle for all
/// connected controllers.
/// Uses dual detection: SwiftUSB for class 0xFF (GIP) +
/// IOKit HIDManager for class 0x03 (HID).
public actor DeviceManager {
  struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
  }

  let parserRegistry: ParserRegistry
  let dispatcher: any OutputDispatcher
  let permissionManager: PermissionManager
  let hidManager: HIDManager
  /// Single libusb context shared across the entire daemon process.
  ///
  /// Creating multiple libusb contexts spins up multiple event threads and can
  /// trigger launchd "inefficient" kills for LaunchAgents.
  var usbContext: USBContext?
  var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  var detectionTasks: [Task<Void, Never>] = []
  var hidDetectionTask: Task<Void, Never>?
  var permissionWatchTask: Task<Void, Never>?
  var externalOutputAllowed = true

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - virtualProfile: Virtual device profile for self-exclusion filtering.
  public init(dispatcher: any OutputDispatcher, virtualProfile: VirtualDeviceProfile = .default) {
    self.dispatcher = dispatcher
    self.parserRegistry = ParserRegistry()
    self.permissionManager = PermissionManager()
    self.hidManager = HIDManager(virtualProfile: virtualProfile)
  }

  /// Start device detection and input processing.
  public func start() async {
    let state = await permissionManager.checkAccess()
    switch state {
    case .unknown, .denied:
      if state == .denied {
        print("[DeviceManager] Input Monitoring denied" + " - running in detect-only mode")
        print(
          "[DeviceManager] Open System Settings" + " > Privacy > Input Monitoring"
            + " to grant access"
        )
      } else {
        print("[DeviceManager] Input Monitoring not yet granted" + " - running in detect-only mode")
        print(
          "[DeviceManager] Use the app's Request Access action" + " to show the native macOS prompt"
        )
      }
    case .granted: print("[DeviceManager] Input Monitoring granted")
    }

    ensureUSBContext()

    let usbTask = Task { await self.runUSBDetection() }
    detectionTasks = [usbTask]
    await ensureHIDDetectionState(for: state)
    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let currentState = await self.permissionManager.checkAccess()
        await self.ensureHIDDetectionState(for: currentState)
        try? await Task.sleep(nanoseconds: devicePermissionWatchNanoseconds)
      }
    }

    print("[DeviceManager] Started" + " - dual detection active")
  }

  /// Returns the latest input snapshot for a device matched by vendor and product ID.
  ///
  /// Returns nil if no pipeline is active for the device.
  public func inputState(for identifier: DeviceIdentifier) -> DeviceInputState? {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }) else { return nil }
    return pipelines[key]?.inputState()
  }

  /// Returns recent raw USB packets for a device matched by vendor and product ID.
  ///
  /// Returns an empty array if no pipeline is active for the device.
  public func packetLog(for identifier: DeviceIdentifier) -> [PacketLogEntry] {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }) else { return [] }
    return pipelines[key]?.getPacketLog() ?? []
  }

  /// Sends a short physical-controller rumble command for a matched USB device.
  public func sendRumble(
    for identifier: DeviceIdentifier,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async -> Bool {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }),
      let pipeline = pipelines[key]
    else { return false }
    let didStartUSB = await pipeline.sendRumble(left: left, right: right, lt: lt, rt: rt)
    let didStartHID =
      didStartUSB
      ? false
      : sendHIDRumbleReport(
        await pipeline.hidRumbleReport(left: left, right: right, lt: lt, rt: rt),
        locationID: key.locationID
      )
    let didStart = didStartUSB || didStartHID
    guard didStart else { return false }
    let clampedDurationMs = max(0, min(durationMs, 5_000))
    if clampedDurationMs > 0 {
      try? await Task.sleep(nanoseconds: UInt64(clampedDurationMs) * 1_000_000)
      let didStopUSB = await pipeline.sendRumble(left: 0, right: 0, lt: 0, rt: 0)
      if !didStopUSB {
        _ = sendHIDRumbleReport(
          await pipeline.hidRumbleReport(left: 0, right: 0, lt: 0, rt: 0),
          locationID: key.locationID
        )
      }
    }
    return true
  }

  func sendHIDRumbleReport(_ report: PhysicalHIDOutputReport?, locationID: UInt32?) -> Bool {
    guard let report, let locationID else { return false }
    return hidManager.setOutputReport(locationID: locationID, report: report)
  }

  /// Returns structured descriptions for all connected controllers.
  ///
  /// Used by XPCService to report live device list.
  public func connectedDeviceDescriptions() -> [XPCDeviceDescription] {
    pipelines.keys.map { id in
      let info = deviceInfos[id]
      let profile = parserRegistry.runtimeProfile(for: id)
      return XPCDeviceDescription(
        name: info?.name ?? "Controller",
        vendorID: id.vendorID,
        productID: id.productID,
        parser: profile.parserName,
        connection: info?.connection ?? "USB",
        serialNumber: info?.serialNumber,
        protocolVariant: profile.protocolVariant.rawValue,
        mappingFlags: profile.mappingFlags,
        inputEndpoint: profile.transportProfile.inputEndpoint,
        outputEndpoint: profile.transportProfile.outputEndpoint,
        needsSetConfiguration: profile.transportProfile.needsSetConfiguration,
        postHandshakeSettleMs: Int(
          profile.transportProfile.postHandshakeSettleNanoseconds / 1_000_000
        ),
        preferredBackends: profile.preferredBackends.map(\.rawValue),
        supportsPhysicalRumble: pipelines[id]?.supportsPhysicalRumble() ?? false
      )
    }
  }

  /// Returns live identifiers for connected controller pipelines.
  public func connectedDeviceIdentifiers() -> [DeviceIdentifier] { Array(pipelines.keys) }

  /// Stop all detection and pipelines.
  public func stop() async {
    for task in detectionTasks { task.cancel() }
    detectionTasks = []
    hidDetectionTask?.cancel()
    hidDetectionTask = nil
    permissionWatchTask?.cancel()
    permissionWatchTask = nil
    for (identifier, pipeline) in pipelines {
      if let locationID = identifier.locationID {
        await sendHIDShutdownFeatureReportsIfNeeded(pipeline: pipeline, locationID: locationID)
      }
      await pipeline.stop()
    }
    pipelines = [:]
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
  }

  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    for pipeline in pipelines.values { await pipeline.setExternalOutputAllowed(allowed) }
  }

}
