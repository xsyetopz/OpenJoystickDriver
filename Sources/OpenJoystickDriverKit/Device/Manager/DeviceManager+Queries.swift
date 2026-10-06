import Foundation

extension DeviceManager {
  /// Returns the latest controller state for a device matched by vendor and product ID.
  ///
  /// Returns nil if no pipeline is active for the device.
  public func controllerState(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil
  ) async -> ControllerState? {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return nil }
    return await pipelines[key]?.inputState()
  }

  /// Returns the ownership evidence for the exact connected device identifier.
  ///
  /// Missing identifiers intentionally fail closed to unknown ownership.
  public func ownershipObservation(
    for identifier: DeviceIdentifier
  ) -> ControllerOwnershipObservation { deviceInfos[identifier]?.ownershipObservation ?? .unknown }

  /// Returns recent raw USB packets for a device matched by vendor and product ID.
  ///
  /// Returns an empty array if no pipeline is active for the device.
  public func packetLog(
    for identifier: DeviceIdentifier,
    runtimeIdentifier: String? = nil
  ) async -> [PacketLogEntry] {
    guard let key = connectedIdentifier(matching: identifier, runtimeIdentifier: runtimeIdentifier)
    else { return [] }
    return await pipelines[key]?.getPacketLog() ?? []
  }

  /// Returns a snapshot of every connected controller.
  /// Used by the application service to report its live device list.
  public func connectedDeviceDescriptions() async -> [ConnectedDeviceSnapshot] {
    var descriptions: [ConnectedDeviceSnapshot] = []
    for id in Array(pipelines.keys) {
      if let description = await deviceDescription(forPipeline: id) {
        descriptions.append(description)
      }
    }
    return descriptions
  }

  /// Describes one connected controller, matched exactly or by runtime identity.
  ///
  /// Output routing calls this per input report, so it builds only the requested description.
  public func deviceDescription(for identifier: DeviceIdentifier) async -> ConnectedDeviceSnapshot?
  {
    // Identifiers without a serial or location share the model-only token; only exact keys match.
    let key =
      pipelines[identifier] != nil
      ? identifier
      : identifier.locationID != nil || identifier.controllerIdentity.serialNumber?.isEmpty == false
        ? pipelines.keys.first { $0.runtimeIdentifier == identifier.runtimeIdentifier } : nil
    guard let key else { return nil }
    return await deviceDescription(forPipeline: key)
  }

  private func deviceDescription(forPipeline id: DeviceIdentifier) async -> ConnectedDeviceSnapshot?
  {
    // A pipeline is registered only after its DeviceInfo; a missing one is mid-teardown.
    guard let pipeline = pipelines[id], let info = deviceInfos[id] else { return nil }
    let record = protocolDriverRegistry.runtimeProfile(for: info.binding)
    // A raw-USB pipeline runs on the profile resolved from the device's descriptor.
    let transportProfile =
      info.usbTransportDevice != nil ? pipeline.transportProfile : record?.transportProfile
    let ownership = info.ownershipObservation
    // A HID key carries an interface only for a protocol role; show the observed one for all.
    let observedInterface: UInt8? =
      if case .hid = info.discoverySource {
        info.physicalDevice?.interfaces?.first?.interfaceNumber
      } else { id.interfaceNumber }
    return ConnectedDeviceSnapshot(
      runtimeIdentifier: id.runtimeIdentifier,
      unitIdentifier: id.unitIdentifier,
      name: info.name,
      vendorID: id.controllerIdentity.vendorID,
      productID: id.controllerIdentity.productID,
      protocolBinding: info.binding.id,
      connection: info.connection,
      interfaceNumber: observedInterface,
      discoverySource: info.discoverySource.kind,
      physicalOwnership: ownership,
      hidInputOwnership: info.hidInputOwnership,
      duplicateExposureRisk: ControllerExposureDecision.decide(
        ownership: ownership,
        intent: .outputDisabled
      ).duplicateRisk,
      serialNumber: info.serialNumber,
      quirks: record?.quirks.map(\.rawValue) ?? [],
      bindingResult: ProtocolBindingResult(
        binding: info.binding,
        interfaces: info.physicalDevice?.interfaces ?? []
      ),
      inputEndpoint: transportProfile?.inputEndpoint ?? 0,
      outputEndpoint: transportProfile?.outputEndpoint ?? 0,
      needsSetConfiguration: transportProfile?.needsSetConfiguration ?? false,
      postHandshakeSettleMs: Int(
        (transportProfile?.postHandshakeSettleNanoseconds ?? 0)
          / deviceDiscoveryNanosecondsPerMillisecond
      ),
      preferredBackends: record?.preferredBackends.map(\.rawValue) ?? [],
      physicalOutputCapabilities: await pipeline.physicalOutputCapabilities(),
      physicalOutputOwner: pipeline.macOSOwnedOutput == nil ? .ojd : .macOS,
      tuning: record?.tuning ?? .none,
      capabilities: protocolDriverRegistry.capabilities(
        await pipeline.capabilities(),
        record: record
      ),
      connectionState: await pipeline.connectionState(
        binding: info.binding,
        interface: info.physicalDevice?.interfaces?.first
      ),
      sessionState: await pipeline.controllerSessionState(),
      startupCommandStatus: await pipeline.startupCommandStatus(),
      inputHealth: await pipeline.inputHealth()
    )
  }

  /// Returns live identifiers for connected controller pipelines.
  public func connectedDeviceIdentifiers() -> [DeviceIdentifier] { Array(pipelines.keys) }

  /// Returns controllers whose sessions can currently publish virtual output.
  public func activeDeviceIdentifiers() async -> [DeviceIdentifier] {
    var identifiers: [DeviceIdentifier] = []
    for (identifier, pipeline) in pipelines where await pipeline.controllerSessionState() == .active
    { identifiers.append(identifier) }
    return identifiers
  }
}
