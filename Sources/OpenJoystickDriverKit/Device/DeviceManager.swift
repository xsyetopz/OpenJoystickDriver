import Foundation
import SwiftUSB

func controllerDisplayName(productName: String?, vendorID: UInt16, productID: UInt16) -> String {
  if let productName {
    let value = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { return value }
  }
  return String(format: "Controller %04x:%04x", vendorID, productID)
}

private let usbDetectionPollNanoseconds: UInt64 = 2_000_000_000
private let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000
private let usbVendorSpecificClass: UInt8 = 0xFF

/// Manages device detection and pipeline lifecycle for all
/// connected controllers.
/// Uses dual detection: SwiftUSB for class 0xFF (GIP) +
/// IOKit HIDManager for class 0x03 (HID).
public actor DeviceManager {
  private struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
  }

  private let parserRegistry: ParserRegistry
  private let dispatcher: any OutputDispatcher
  private let permissionManager: PermissionManager
  private let hidManager: HIDManager
  /// Single libusb context shared across the entire daemon process.
  ///
  /// Creating multiple libusb contexts spins up multiple event threads and can
  /// trigger launchd "inefficient" kills for LaunchAgents.
  private var usbContext: USBContext?
  private var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  private var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  private var detectionTasks: [Task<Void, Never>] = []
  private var hidDetectionTask: Task<Void, Never>?
  private var permissionWatchTask: Task<Void, Never>?
  private var externalOutputAllowed = true
  private var lastPhysicalHIDOutputNanoseconds: [DeviceIdentifier: UInt64] = [:]

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - virtualProfile: Virtual device profile for self-exclusion filtering.
  public init(dispatcher: any OutputDispatcher, virtualProfile: VirtualDeviceProfile = .default) {
    self.dispatcher = dispatcher
    let registry = ParserRegistry()
    self.parserRegistry = registry
    self.permissionManager = PermissionManager()
    self.hidManager = HIDManager(
      virtualProfile: virtualProfile,
      additionalProfileIdentifiers: registry.hidProfileIdentifiers()
    )
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
    let featureHaptics = await pipeline.hidFeatureHapticReports(
      left: left,
      right: right,
      durationMs: durationMs
    )
    if !featureHaptics.isEmpty, let locationID = key.locationID {
      return featureHaptics.allSatisfy {
        hidManager.setFeatureReport(locationID: locationID, report: $0)
      }
    }

    let didStartUSB = await pipeline.sendRumble(left: left, right: right, lt: lt, rt: rt)
    if !didStartUSB { await enforcePhysicalHIDOutputInterval(for: key, pipeline: pipeline) }
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
        await enforcePhysicalHIDOutputInterval(for: key, pipeline: pipeline)
        _ = sendHIDRumbleReport(
          await pipeline.hidRumbleReport(left: 0, right: 0, lt: 0, rt: 0),
          locationID: key.locationID
        )
      }
    }
    return true
  }

  /// Sets an RGB physical lightbar when the active protocol supports it.
  public func setPhysicalColor(
    for identifier: DeviceIdentifier,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async -> Bool {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }),
      let pipeline = pipelines[key], let locationID = key.locationID,
      let report = await pipeline.hidColorReport(red: red, green: green, blue: blue)
    else { return false }
    await enforcePhysicalHIDOutputInterval(for: key, pipeline: pipeline)
    return hidManager.setOutputReport(locationID: locationID, report: report)
  }

  /// Sets scalar physical LED brightness when the active protocol supports it.
  public func setPhysicalBrightness(for identifier: DeviceIdentifier, brightness: UInt8) async
    -> Bool
  {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }),
      let pipeline = pipelines[key], let locationID = key.locationID,
      let report = await pipeline.hidBrightnessReport(brightness)
    else { return false }
    return hidManager.setFeatureReport(locationID: locationID, report: report)
  }

  /// Sets the physical numbered player indicator when the active protocol supports it.
  public func sendPlayerIndicator(
    for identifier: DeviceIdentifier,
    indicator: PhysicalPlayerIndicator
  ) async -> Bool {
    guard let key = pipelines.keys.first(where: { $0.modelMatches(identifier) }),
      let pipeline = pipelines[key]
    else { return false }
    let didSendUSB = await pipeline.sendPlayerIndicator(indicator)
    if didSendUSB { return true }
    guard let locationID = key.locationID,
      let report = await pipeline.hidPlayerIndicatorReport(indicator)
    else { return false }
    await enforcePhysicalHIDOutputInterval(for: key, pipeline: pipeline)
    return hidManager.setOutputReport(locationID: locationID, report: report)
  }

  private func enforcePhysicalHIDOutputInterval(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline
  ) async {
    let minimum = pipeline.minimumPhysicalOutputIntervalNanoseconds()
    guard minimum > 0 else { return }
    while true {
      let now = DispatchTime.now().uptimeNanoseconds
      let previous = lastPhysicalHIDOutputNanoseconds[identifier] ?? 0
      let elapsed = now >= previous ? now - previous : minimum
      if elapsed >= minimum {
        lastPhysicalHIDOutputNanoseconds[identifier] = now
        return
      }
      try? await Task.sleep(nanoseconds: minimum - elapsed)
    }
  }

  private func sendHIDRumbleReport(_ report: PhysicalHIDOutputReport?, locationID: UInt32?) -> Bool
  {
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
        supportsPhysicalRumble: pipelines[id]?.supportsPhysicalRumble() ?? false,
        physicalOutputCapabilities: (pipelines[id]?.physicalOutputCapabilities() ?? .none)
          .withEvidence(profile.hardwareVerified ? .hardwareVerified : .sourceBacked)
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
    lastPhysicalHIDOutputNanoseconds = [:]
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
  }

  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    for pipeline in pipelines.values { await pipeline.setExternalOutputAllowed(allowed) }
  }

  // MARK: - USB detection (class 0xFF)

  private func runUSBDetection() async {
    print("[DeviceManager] USB detection started" + " (class 0xFF)")
    ensureUSBContext()
    guard let context = usbContext else {
      print("[DeviceManager] Failed to create USBContext")
      return
    }

    var knownLocations: Set<String> = []
    var locationToIdentifier: [String: DeviceIdentifier] = [:]

    while !Task.isCancelled {
      let (currentKeys, addedDevices) = await usbDetectCurrentDevices(
        context: context,
        knownLocations: knownLocations
      )

      updateUSBKnownLocations(
        &knownLocations,
        currentKeys: currentKeys,
        addedDevices: addedDevices,
        locationToIdentifier: &locationToIdentifier
      )

      await removeUSBLostDevices(
        knownLocations: &knownLocations,
        currentKeys: currentKeys,
        locationToIdentifier: &locationToIdentifier
      )

      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  private func usbDetectCurrentDevices(context: USBContext, knownLocations: Set<String>) async -> (
    Set<String>, [(device: USBDevice, key: String)]
  ) {
    var currentKeys: Set<String> = []
    var addedDevices: [(device: USBDevice, key: String)] = []
    let stream = context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
    for await device in stream {
      let key = "\(device.bus):\(device.address)"
      currentKeys.insert(key)
      if !knownLocations.contains(key) { addedDevices.append((device, key)) }
    }
    return (currentKeys, addedDevices)
  }

  private func updateUSBKnownLocations(
    _ knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    addedDevices: [(device: USBDevice, key: String)],
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) {
    for (device, key) in addedDevices {
      knownLocations.insert(key)
      if let id = handleUSBDeviceAdded(device) { locationToIdentifier[key] = id }
    }
  }

  private func removeUSBLostDevices(
    knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) async {
    let removedKeys = knownLocations.subtracting(currentKeys)
    for key in removedKeys {
      knownLocations.remove(key)
      if let id = locationToIdentifier.removeValue(forKey: key) {
        let pipeline = pipelines.removeValue(forKey: id)
        deviceInfos.removeValue(forKey: id)
        lastPhysicalHIDOutputNanoseconds.removeValue(forKey: id)
        await pipeline?.stop()
        print("[DeviceManager] USB device removed: \(id)")
      }
    }
  }

  private func ensureUSBContext() {
    if usbContext != nil { return }
    do { usbContext = try USBContext() } catch {
      usbContext = nil
      print("[DeviceManager] Failed to create USBContext: \(error)")
    }
  }

  @discardableResult private func handleUSBDeviceAdded(_ device: USBDevice) -> DeviceIdentifier? {
    let locationID = UInt32((UInt32(device.bus) << 8) | UInt32(device.address))
    let serial = try? device.getSerialNumber()
    let identifier = DeviceIdentifier(
      vendorID: device.idVendor,
      productID: device.idProduct,
      serialNumber: serial,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else {
      print("[DeviceManager] Pipeline already exists" + " for \(identifier)")
      return nil
    }

    let productName = controllerDisplayName(
      productName: try? device.getProduct(),
      vendorID: device.idVendor,
      productID: device.idProduct
    )
    deviceInfos[identifier] = DeviceInfo(name: productName, connection: "USB", serialNumber: serial)
    print("[DeviceManager] USB device added: \(productName) (\(identifier))")
    let configuredTransport = parserRegistry.transportProfile(for: identifier)
    let transportProfile = USBDescriptorTransportResolver.resolve(
      device: device,
      configured: configuredTransport
    )
    let parser = parserRegistry.parser(for: identifier, transportProfile: transportProfile)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(vendorID: device.idVendor, productID: device.idProduct),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: usbContext,
      transportProfile: transportProfile,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    if !pipeline.requiresInputConnectionBeforeOutput() {
      Task { await dispatcher.dispatch(events: [], from: identifier) }
    }
    return identifier
  }

  // MARK: - HID detection (class 0x03)

  private func ensureHIDDetectionState(for state: PermissionManager.AccessState) async {
    switch state {
    case .granted:
      guard hidDetectionTask == nil else { return }
      hidDetectionTask = Task { await self.runHIDDetection() }
    case .unknown, .denied:
      hidDetectionTask?.cancel()
      hidDetectionTask = nil
      await removeHIDPipelines()
    }
  }

  private func runHIDDetection() async {
    print("[DeviceManager] HID detection started" + " (class 0x03)")
    for await event in hidManager.deviceEvents() {
      switch event {
      case .connected(let vid, let pid, let serial, let loc, let productName, let transport):
        handleHIDDeviceConnected(
          vendorID: vid,
          productID: pid,
          serialNumber: serial,
          locationID: loc,
          productName: productName,
          transport: transport
        )
      case .disconnected(let vid, let pid, let loc):
        await handleHIDDeviceDisconnected(vendorID: vid, productID: pid, locationID: loc)
      case .inputReport(let loc, _, let data):
        await routeHIDInputReport(locationID: loc, data: data)
      case .inputValue(let loc, let value):
        await routeHIDElementValue(locationID: loc, value: value)
      }
    }
  }

  private func removeHIDPipelines() async {
    let hidIdentifiers = pipelines.keys.filter { (deviceInfos[$0]?.connection ?? "") != "USB" }

    for identifier in hidIdentifiers {
      guard let pipeline = pipelines.removeValue(forKey: identifier) else { continue }
      deviceInfos.removeValue(forKey: identifier)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
      await pipeline.stop()
      print("[DeviceManager] HID pipeline removed: \(identifier)")
    }
  }

  private func handleHIDDeviceConnected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?,
    transport: String?
  ) {
    let identifier = DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serialNumber,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else { return }

    let name = controllerDisplayName(
      productName: productName,
      vendorID: vendorID,
      productID: productID
    )
    let connection = transport ?? "HID"
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: connection,
      serialNumber: serialNumber
    )
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser: any InputParser
    if parserRegistry.parserName(for: identifier) == "DS4", connection == "Bluetooth" {
      parser = DS4Parser(prefersBluetooth: true)
    } else if parserRegistry.parserName(for: identifier) == "DualSense" {
      parser = DualSenseParser(prefersBluetooth: connection == "Bluetooth")
    } else {
      parser = parserRegistry.parser(for: identifier)
    }
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: locationID),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: nil,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    if !pipeline.requiresInputConnectionBeforeOutput() {
      Task { await dispatcher.dispatch(events: [], from: identifier) }
    }
    sendHIDStartupFeatureReadRequestsIfNeeded(
      parser: parser,
      locationID: locationID,
      transport: transport
    )
    if !pipeline.requiresInputConnectionBeforeOutput() {
      sendHIDStartupFeatureReportsIfNeeded(
        parser: parser,
        locationID: locationID,
        transport: transport
      )
    }
    sendHIDStartupOutputReportsIfNeeded(
      parser: parser,
      locationID: locationID,
      transport: transport
    )
    requestHIDInputConnectionStatusIfNeeded(parser: parser, locationID: locationID)
  }

  private func sendHIDStartupFeatureReadRequestsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReadRequestProvider else { return }
    for request in provider.hidStartupFeatureReadRequests(transport: transport)
    where hidManager.getFeatureReport(locationID: locationID, request: request) == nil {
      print("[DeviceManager] HID startup feature report read failed for loc=\(locationID)")
    }
  }

  private func sendHIDStartupFeatureReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReportProvider else { return }
    for report in provider.hidStartupFeatureReports(transport: transport) {
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent { print("[DeviceManager] HID startup feature report failed for loc=\(locationID)") }
    }
  }

  private func sendHIDStartupOutputReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupOutputReportProvider else { return }
    let reports = provider.hidStartupReports(transport: transport)
    let interval = provider.hidStartupReportIntervalNanoseconds(transport: transport)
    if interval == 0 {
      for report in reports {
        let sent = hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
      return
    }
    Task { [hidManager] in
      for (index, report) in reports.enumerated() {
        if index > 0 { try? await Task.sleep(nanoseconds: interval) }
        let sent = hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
    }
  }

  private func requestHIDInputConnectionStatusIfNeeded(parser: any InputParser, locationID: UInt32)
  {
    guard let requester = parser as? any HIDInputConnectionStatusRequester,
      let report = requester.inputConnectionStatusRequestReport()
    else { return }
    let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
    if !sent {
      print("[DeviceManager] HID input connection status request failed for loc=\(locationID)")
    }
  }

  private func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
    async
  {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      let pipeline = pipelines.removeValue(forKey: key)
      deviceInfos.removeValue(forKey: key)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: key)
      await sendHIDShutdownFeatureReportsIfNeeded(pipeline: pipeline, locationID: locationID)
      await pipeline?.stop()
      print(
        "[DeviceManager] HID device disconnected:" + " VID=\(vendorID) PID=\(productID)"
          + " loc=\(locationID)"
      )
    }
  }

  private func sendHIDShutdownFeatureReportsIfNeeded(pipeline: DevicePipeline?, locationID: UInt32)
    async
  {
    guard let pipeline else { return }
    for report in await pipeline.hidShutdownFeatureReports() {
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent { print("[DeviceManager] HID shutdown feature report failed for loc=\(locationID)") }
    }
  }

  private func routeHIDElementValue(locationID: UInt32, value: HIDElementValue) async {
    guard let key = pipelines.keys.first(where: { $0.locationID == locationID }),
      let pipeline = pipelines[key]
    else { return }
    await pipeline.feedHIDElementValue(value)
  }

  private func routeHIDInputReport(locationID: UInt32, data: Data) async {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }),
      let featureReports = await pipelines[key]?.feedHIDData(data)
    {
      for report in featureReports {
        let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
        if !sent {
          print("[DeviceManager] HID lifecycle feature report failed for loc=\(locationID)")
        }
      }
    }
  }
}
