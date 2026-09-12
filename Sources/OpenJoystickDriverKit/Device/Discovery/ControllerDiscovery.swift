import Foundation

func controllerDisplayName(productName: String?, vendorID: UInt16, productID: UInt16) -> String {
  if let productName {
    let value = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { return value }
  }
  return String(format: "Controller %04x:%04x", vendorID, productID)
}

let usbDetectionPollNanoseconds: UInt64 = 500_000_000
let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000
private let nanosecondsPerMillisecond: UInt64 = 1_000_000
let maxRumbleDurationMs = 5_000
let usbVendorSpecificClass: UInt8 = 0xFF

struct RumbleStopTokenRegistry {
  private var generations: [DeviceIdentifier: UInt64] = [:]

  mutating func replace(for identifier: DeviceIdentifier) -> UInt64 {
    let generation = (generations[identifier] ?? 0) &+ 1
    generations[identifier] = generation
    return generation
  }

  func isCurrent(_ generation: UInt64, for identifier: DeviceIdentifier) -> Bool {
    generations[identifier] == generation
  }

  mutating func remove(_ identifier: DeviceIdentifier) {
    generations.removeValue(forKey: identifier)
  }

  mutating func removeAll() { generations.removeAll() }
}

/// Manages device detection and pipeline lifecycle for all
/// connected controllers.
/// Uses dual detection: an Apple USB transport provider for raw interfaces and
/// the OS-generation HID wrapper for HID-class controllers.
public actor DeviceManager {
  enum DiscoverySource {
    case hid
    case rawUSB(route: USBTransportRoute)

    var requiresInputMonitoring: Bool {
      if case .hid = self { return true }
      return false
    }

    var applicationServiceValue: ApplicationServiceDeviceDiscoverySource {
      switch self {
      case .hid: .hid
      case .rawUSB: .rawUSB
      }
    }

    var ownershipObservation: ControllerOwnershipObservation {
      switch self {
      case .hid: .nativeHIDVisible
      case .rawUSB(.ioUSBHost): .exclusiveRawUSB
      case .rawUSB(.usbDriverKit): .driverKitOwnedUSB
      }
    }
  }

  struct DeviceInfo {
    let name: String
    let connection: String
    let serialNumber: String?
    let discoverySource: DiscoverySource
    var hidInputOwnership: HIDInputOwnership = .unknown

    var ownershipObservation: ControllerOwnershipObservation {
      if case .hid = discoverySource, hidInputOwnership == .exclusive { return .exclusiveHID }
      return discoverySource.ownershipObservation
    }
  }

  let parserRegistry: ParserRegistry
  let dispatcher: any OutputDispatcher
  let permissionManager: PermissionManager
  let hidManager: HIDManager
  let usbTransportProvider: (any USBTransportProvider)?
  var pipelines: [DeviceIdentifier: DevicePipeline] = [:]
  var deviceInfos: [DeviceIdentifier: DeviceInfo] = [:]
  var detectionTasks: [Task<Void, Never>] = []
  var hidDetectionTask: Task<Void, Never>?
  var permissionWatchTask: Task<Void, Never>?
  var externalOutputAllowed = true
  var lastPhysicalHIDOutputNanoseconds: [DeviceIdentifier: UInt64] = [:]
  var rumbleStopTasks: [DeviceIdentifier: Task<Void, Never>] = [:]
  var rumbleStopTokens = RumbleStopTokenRegistry()
  var physicalOutputOwnership = PhysicalOutputOwnership()

  /// Creates a manager that sends all output to `dispatcher`.
  ///
  /// - Parameters:
  ///   - dispatcher: Output dispatcher for sending HID reports.
  ///   - virtualProfile: Virtual device profile for self-exclusion filtering.
  ///   - usbTransportProvider: Native raw-USB transport provider, or nil to disable raw USB
  ///     discovery.
  public init(
    dispatcher: any OutputDispatcher,
    virtualProfile: VirtualDeviceProfile = .default,
    usbTransportProvider: (any USBTransportProvider)? = nil
  ) {
    self.dispatcher = dispatcher
    self.usbTransportProvider = usbTransportProvider
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
    let state = await permissionManager.checkAccess().inputMonitoring
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

    if usbTransportProvider != nil {
      detectionTasks = [Task { await self.runUSBDetection() }]
    } else {
      detectionTasks = []
    }
    await ensureHIDDetectionState(for: state)
    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let currentState = await self.permissionManager.checkAccess().inputMonitoring
        await self.ensureHIDDetectionState(for: currentState)
        try? await Task.sleep(nanoseconds: devicePermissionWatchNanoseconds)
      }
    }

    print("[DeviceManager] Started" + " - dual detection active")
  }

  /// Returns the latest input snapshot for a device matched by vendor and product ID.
  ///
  /// Returns nil if no pipeline is active for the device.
  public func inputState(for identifier: DeviceIdentifier, runtimeIdentifier: String? = nil)
    -> DeviceInputState?
  {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return nil }
    return pipelines[key]?.inputState()
  }

  /// Returns the ownership evidence for the exact connected device identifier.
  ///
  /// Missing identifiers intentionally fail closed to unknown ownership.
  public func ownershipObservation(for identifier: DeviceIdentifier)
    -> ControllerOwnershipObservation
  { deviceInfos[identifier]?.ownershipObservation ?? .unknown }

  /// Returns recent raw USB packets for a device matched by vendor and product ID.
  ///
  /// Returns an empty array if no pipeline is active for the device.
  public func packetLog(for identifier: DeviceIdentifier, runtimeIdentifier: String? = nil)
    -> [PacketLogEntry]
  {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return [] }
    return pipelines[key]?.getPacketLog() ?? []
  }

  /// Sends a short physical-controller rumble command for a matched USB device.
  public func sendRumble(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async -> Bool {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier),
      let pipeline = pipelines[key]
    else { return false }
    let values: [(PhysicalRumbleMotor, UInt8)] = [
      (.leftMain, left), (.rightMain, right), (.leftTrigger, lt), (.rightTrigger, rt),
      (.leftHaptic, left), (.rightHaptic, right),
    ]
    let supportedMotors = Set(pipeline.physicalOutputCapabilities().rumbleMotors)
    guard values.contains(where: { supportedMotors.contains($0.0) }) else { return false }
    let previousOwnership = physicalOutputOwnership
    for (motor, value) in values where supportedMotors.contains(motor) {
      _ = physicalOutputOwnership.setManual(
        .rumble(motor: motor, intensity: Double(value) / 255),
        for: key
      )
    }
    guard await sendEffectiveRumble(for: key, pipeline: pipeline, durationMs: durationMs) else {
      physicalOutputOwnership = previousOwnership
      return false
    }
    let clampedDurationMs = max(0, min(durationMs, maxRumbleDurationMs))
    if clampedDurationMs == 0 {
      _ = physicalOutputOwnership.releaseManualRumble(for: key)
      return await sendEffectiveRumble(for: key, pipeline: pipeline, durationMs: 0)
    }
    scheduleRumbleStop(
      for: key,
      pipeline: pipeline,
      durationMs: clampedDurationMs,
      hasActiveMotor: left != 0 || right != 0 || lt != 0 || rt != 0
    )
    return true
  }

  private func scheduleRumbleStop(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    durationMs: Int,
    hasActiveMotor: Bool
  ) {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    let generation = rumbleStopTokens.replace(for: identifier)
    guard durationMs > 0, hasActiveMotor else {
      rumbleStopTokens.remove(identifier)
      return
    }
    rumbleStopTasks[identifier] = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: UInt64(durationMs) * nanosecondsPerMillisecond) } catch
      { return }
      await self?.finishScheduledRumbleStop(
        for: identifier,
        pipeline: pipeline,
        generation: generation
      )
    }
  }

  private func finishScheduledRumbleStop(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    generation: UInt64
  ) async {
    guard rumbleStopTokens.isCurrent(generation, for: identifier),
      pipelines[identifier] === pipeline
    else { return }
    _ = physicalOutputOwnership.releaseManualRumble(for: identifier)
    _ = await sendEffectiveRumble(for: identifier, pipeline: pipeline, durationMs: 0)
    guard rumbleStopTokens.isCurrent(generation, for: identifier) else { return }
    rumbleStopTasks.removeValue(forKey: identifier)
    rumbleStopTokens.remove(identifier)
  }

  /// Sets an RGB physical lightbar when the active protocol supports it.
  public func setPhysicalColor(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async -> Bool {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier),
      let pipeline = pipelines[key],
      pipeline.physicalOutputCapabilities().lightingFeatures.contains(.programmableColor)
    else { return false }
    let previousOwnership = physicalOutputOwnership
    _ = physicalOutputOwnership.setManual(.color(red: red, green: green, blue: blue), for: key)
    let delivered = await applyPhysicalChannel(.color, for: key, pipeline: pipeline)
    if !delivered { physicalOutputOwnership = previousOwnership }
    return delivered
  }

  /// Sets scalar physical LED brightness when the active protocol supports it.
  public func setPhysicalBrightness(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil,
    brightness: UInt8
  ) async -> Bool {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier),
      let pipeline = pipelines[key],
      pipeline.physicalOutputCapabilities().lightingFeatures.contains(.programmableBrightness)
    else { return false }
    let previousOwnership = physicalOutputOwnership
    _ = physicalOutputOwnership.setManual(
      .brightness(Double(brightness) / 255),
      for: key
    )
    let delivered = await applyPhysicalChannel(.brightness, for: key, pipeline: pipeline)
    if !delivered { physicalOutputOwnership = previousOwnership }
    return delivered
  }

  /// Sets the physical numbered player indicator when the active protocol supports it.
  public func sendPlayerIndicator(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil,
    indicator: PhysicalPlayerIndicator
  ) async -> Bool {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier),
      let pipeline = pipelines[key],
      pipeline.physicalOutputCapabilities().lightingFeatures.contains(.playerIndicator)
    else { return false }
    let previousOwnership = physicalOutputOwnership
    _ = physicalOutputOwnership.setManual(.playerIndicator(indicator), for: key)
    let delivered = await applyPhysicalChannel(.playerIndicator, for: key, pipeline: pipeline)
    if !delivered { physicalOutputOwnership = previousOwnership }
    return delivered
  }

  /// Applies or releases one remapping claim for an exact connected controller.
  public func setMappingPhysicalOutput(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) async -> Bool {
    do { try output.validate() } catch { return false }
    guard let pipeline = pipelines[identifier] else {
      if !active {
        _ = physicalOutputOwnership.setMapping(
          output, active: false, owner: owner, for: identifier
        )
        return true
      }
      return false
    }
    guard supports(output, capabilities: pipeline.physicalOutputCapabilities()) else {
      return false
    }
    let previousOwnership = physicalOutputOwnership
    let channel = physicalOutputOwnership.setMapping(
      output, active: active, owner: owner, for: identifier
    )
    let delivered = await applyPhysicalChannel(channel, for: identifier, pipeline: pipeline)
    if !delivered { physicalOutputOwnership = previousOwnership }
    return delivered
  }

  /// Releases every remapping claim for an exact controller without targeting a replacement.
  public func releaseMappingPhysicalOutputs(for identifier: DeviceIdentifier) async -> Bool {
    let channels = physicalOutputOwnership.releaseMappings(for: identifier)
    guard let pipeline = pipelines[identifier] else { return true }
    var delivered = true
    for channel in channels.sorted(by: { $0.sortKey < $1.sortKey }) {
      guard await applyPhysicalChannel(channel, for: identifier, pipeline: pipeline) else {
        delivered = false
        continue
      }
    }
    return delivered
  }

  private func supports(
    _ output: RemappingPhysicalOutput,
    capabilities: PhysicalControllerOutputCapabilities
  ) -> Bool {
    switch output {
    case .rumble(let motor, _): capabilities.rumbleMotors.contains(motor)
    case .playerIndicator: capabilities.lightingFeatures.contains(.playerIndicator)
    case .color: capabilities.lightingFeatures.contains(.programmableColor)
    case .brightness: capabilities.lightingFeatures.contains(.programmableBrightness)
    case .adaptiveTrigger(let trigger, _): capabilities.adaptiveTriggers.contains(trigger)
    }
  }

  private func applyPhysicalChannel(
    _ channel: PhysicalOutputChannel,
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline
  ) async -> Bool {
    switch channel {
    case .rumble:
      return await sendEffectiveRumble(for: identifier, pipeline: pipeline, durationMs: 0)
    case .playerIndicator:
      let indicator: PhysicalPlayerIndicator
      if case .playerIndicator(let value) = physicalOutputOwnership.effectiveOutput(
        for: channel, device: identifier
      ) {
        indicator = value
      } else {
        indicator = .off
      }
      let didSendUSB = await pipeline.sendPlayerIndicator(indicator)
      if didSendUSB { return true }
      guard let locationID = identifier.locationID,
        let report = await pipeline.hidPlayerIndicatorReport(indicator)
      else { return false }
      do { try await enforcePhysicalHIDOutputInterval(for: identifier, pipeline: pipeline) } catch {
        return false
      }
      return await hidManager.setOutputReport(locationID: locationID, report: report)
    case .color:
      let value = physicalOutputOwnership.effectiveOutput(for: channel, device: identifier)
      let components: (UInt8, UInt8, UInt8)
      if case .color(let red, let green, let blue) = value {
        components = (red, green, blue)
      } else {
        components = (0, 0, 0)
      }
      guard let locationID = identifier.locationID,
        let report = await pipeline.hidColorReport(
          red: components.0, green: components.1, blue: components.2
        )
      else { return false }
      do { try await enforcePhysicalHIDOutputInterval(for: identifier, pipeline: pipeline) } catch {
        return false
      }
      return await hidManager.setOutputReport(locationID: locationID, report: report)
    case .brightness:
      let value = physicalOutputOwnership.effectiveOutput(for: channel, device: identifier)
      let brightness: UInt8
      if case .brightness(let intensity) = value {
        brightness = UInt8((intensity * 255).rounded())
      } else {
        brightness = 0
      }
      guard let locationID = identifier.locationID,
        let report = await pipeline.hidBrightnessReport(brightness)
      else { return false }
      return await hidManager.setFeatureReport(locationID: locationID, report: report)
    case .adaptiveTrigger(let trigger):
      let value = physicalOutputOwnership.effectiveOutput(for: channel, device: identifier)
      let effect: PhysicalAdaptiveTriggerEffect
      if case .adaptiveTrigger(_, let currentEffect) = value {
        effect = currentEffect
      } else {
        effect = .off
      }
      guard let locationID = identifier.locationID,
        let report = await pipeline.hidAdaptiveTriggerReport(trigger, effect: effect)
      else { return false }
      do { try await enforcePhysicalHIDOutputInterval(for: identifier, pipeline: pipeline) } catch {
        return false
      }
      return await hidManager.setOutputReport(locationID: locationID, report: report)
    }
  }

  private func sendEffectiveRumble(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    durationMs: Int
  ) async -> Bool {
    func byte(for motor: PhysicalRumbleMotor) -> UInt8 {
      guard case .rumble(_, let intensity) = physicalOutputOwnership.effectiveOutput(
        for: .rumble(motor), device: identifier
      ) else { return 0 }
      return UInt8((intensity * 255).rounded())
    }
    let left = byte(for: .leftMain)
    let right = byte(for: .rightMain)
    let lt = byte(for: .leftTrigger)
    let rt = byte(for: .rightTrigger)
    let featureHaptics = await pipeline.hidFeatureHapticReports(
      left: byte(for: .leftHaptic),
      right: byte(for: .rightHaptic),
      durationMs: durationMs
    )
    if pipeline.supportsHIDFeatureHaptics() {
      guard let locationID = identifier.locationID else { return false }
      for report in featureHaptics
      where !(await hidManager.setFeatureReport(locationID: locationID, report: report)) {
        return false
      }
      return true
    }
    let didSendUSB = await pipeline.sendRumble(left: left, right: right, lt: lt, rt: rt)
    if didSendUSB { return true }
    do { try await enforcePhysicalHIDOutputInterval(for: identifier, pipeline: pipeline) } catch {
      return false
    }
    return await sendHIDRumbleReport(
      await pipeline.hidRumbleReport(left: left, right: right, lt: lt, rt: rt),
      locationID: identifier.locationID
    )
  }

  func neutralizePhysicalOutputs(for identifier: DeviceIdentifier, pipeline: DevicePipeline) async {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    rumbleStopTokens.remove(identifier)
    physicalOutputOwnership.removeDevice(identifier)
    let capabilities = pipeline.physicalOutputCapabilities()
    var channels = Set(capabilities.rumbleMotors.map(PhysicalOutputChannel.rumble))
    if capabilities.lightingFeatures.contains(.playerIndicator) {
      channels.insert(.playerIndicator)
    }
    if capabilities.lightingFeatures.contains(.programmableColor) { channels.insert(.color) }
    if capabilities.lightingFeatures.contains(.programmableBrightness) {
      channels.insert(.brightness)
    }
    channels.formUnion(capabilities.adaptiveTriggers.map(PhysicalOutputChannel.adaptiveTrigger))
    for channel in channels.sorted(by: { $0.sortKey < $1.sortKey }) {
      _ = await applyPhysicalChannel(channel, for: identifier, pipeline: pipeline)
    }
  }

  private func connectedIdentifier(matching model: DeviceIdentifier, runtimeIdentifier: String?)
    -> DeviceIdentifier?
  {
    Self.connectedIdentifier(
      among: pipelines.keys,
      matching: model,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  static func connectedIdentifier<Identifiers: Sequence>(
    among identifiers: Identifiers,
    matching model: DeviceIdentifier,
    runtimeIdentifier: String?
  ) -> DeviceIdentifier? where Identifiers.Element == DeviceIdentifier {
    let matches = identifiers.filter {
      $0.modelMatches(model)
        && (runtimeIdentifier == nil || $0.runtimeIdentifier == runtimeIdentifier)
    }
    return matches.count == 1 ? matches.first : nil
  }

  static func matchingPhysicalIdentifier<Identifiers: Sequence>(
    for candidate: DeviceIdentifier,
    among identifiers: Identifiers
  ) -> DeviceIdentifier? where Identifiers.Element == DeviceIdentifier {
    identifiers.first { $0.exactlyMatches(candidate) }
  }

  private func enforcePhysicalHIDOutputInterval(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline
  ) async throws {
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
      try await Task.sleep(nanoseconds: minimum - elapsed)
    }
  }

  private func sendHIDRumbleReport(_ report: PhysicalHIDOutputReport?, locationID: UInt32?) async
    -> Bool
  {
    guard let report, let locationID else { return false }
    return await hidManager.setOutputReport(locationID: locationID, report: report)
  }

  /// Returns structured descriptions for all connected controllers.
  ///
  /// Used by the application service to report its live device list.
  public func connectedDeviceDescriptions() -> [ApplicationServiceDeviceDescription] {
    pipelines.keys.map { id in
      let info = deviceInfos[id]
      let profile = parserRegistry.runtimeProfile(for: id)
      let ownership = info?.ownershipObservation ?? .unknown
      return ApplicationServiceDeviceDescription(
        name: info?.name ?? "Controller",
        vendorID: id.vendorID,
        productID: id.productID,
        parser: profile.parserName,
        connection: info?.connection ?? "USB",
        discoverySource: info?.discoverySource.applicationServiceValue ?? .unknown,
        physicalOwnership: ownership,
        hidInputOwnership: info?.hidInputOwnership ?? .unknown,
        duplicateExposureRisk: ControllerExposureDecision.decide(
          ownership: ownership,
          intent: .outputDisabled
        ).duplicateRisk,
        serialNumber: info?.serialNumber,
        protocolVariant: profile.protocolVariant,
        quirks: profile.quirks,
        inputEndpoint: profile.transportProfile.inputEndpoint,
        outputEndpoint: profile.transportProfile.outputEndpoint,
        needsSetConfiguration: profile.transportProfile.needsSetConfiguration,
        postHandshakeSettleMs: Int(
          profile.transportProfile.postHandshakeSettleNanoseconds / nanosecondsPerMillisecond
        ),
        preferredBackends: profile.preferredBackends.map(\.rawValue),
        physicalOutputCapabilities: pipelines[id]?.physicalOutputCapabilities() ?? .none,
        physicalInputCapabilities: pipelines[id]?.physicalInputCapabilities() ?? .none,
        runtimeIdentifier: id.runtimeIdentifier
      )
    }
  }

  /// Returns live identifiers for connected controller pipelines.
  public func connectedDeviceIdentifiers() -> [DeviceIdentifier] { Array(pipelines.keys) }

  /// Stop all detection and pipelines.
  public func stop() async {
    for task in rumbleStopTasks.values { task.cancel() }
    rumbleStopTasks = [:]
    rumbleStopTokens.removeAll()
    for task in detectionTasks { task.cancel() }
    detectionTasks = []
    hidDetectionTask?.cancel()
    hidDetectionTask = nil
    permissionWatchTask?.cancel()
    permissionWatchTask = nil
    for (identifier, pipeline) in pipelines {
      await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
      if let locationID = identifier.locationID {
        await sendHIDShutdownFeatureReportsIfNeeded(pipeline: pipeline, locationID: locationID)
      }
      await pipeline.stop()
    }
    pipelines = [:]
    physicalOutputOwnership.removeAll()
    lastPhysicalHIDOutputNanoseconds = [:]
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
  }

  /// Enables or suppresses application-facing compatibility output for every active pipeline.
  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    for pipeline in pipelines.values { await pipeline.setExternalOutputAllowed(allowed) }
  }
}
