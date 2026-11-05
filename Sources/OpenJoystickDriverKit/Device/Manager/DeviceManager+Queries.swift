import Foundation

extension DeviceManager {
  /// Returns the latest controller state of the one connected controller `controller` names.
  ///
  /// Returns nil when no controller, or more than one, matches.
  public func controllerState(
    for controller: ControllerReference
  ) async -> ControllerState? {
    guard let key = await connectedIdentifier(for: controller)
    else { return nil }
    return await pipelines[key]?.inputState()
  }

  /// Returns the ownership evidence for the exact connected device identifier.
  ///
  /// Missing identifiers intentionally fail closed to unknown ownership.
  public func ownershipObservation(
    for identifier: LogicalControllerID
  ) -> ControllerOwnershipObservation { deviceInfos[identifier]?.ownershipObservation ?? .unknown }

  /// Returns recent raw USB packets of the one connected controller `controller` names.
  ///
  /// Returns an empty array when no controller, or more than one, matches.
  public func packetLog(
    for controller: ControllerReference
  ) async -> [PacketLogEntry] {
    guard let key = await connectedIdentifier(for: controller)
    else { return [] }
    return await pipelines[key]?.getPacketLog() ?? []
  }

  /// Returns the frame timings of every connected controller: the frames read within
  /// `lastSeconds` seconds before `now` on the uptime clock, or the whole ring when `lastSeconds`
  /// is nil.
  public func frameTimingsSnapshot(
    lastSeconds: Int?,
    now: UInt64
  ) async -> ApplicationServiceFrameTimingsPayload {
    ApplicationServiceFrameTimingsPayload(
      controllers: await connectedDeviceDescriptions().map { description in
        let identifier = description.logicalControllerID
        return ControllerFrameTimings(
          controller: description.sessionToken.rawValue,
          name: description.name,
          window: lastSeconds.map { seconds in
            frameTimings.window(for: identifier, lastSeconds: seconds, now: now)
          } ?? frameTimings.window(for: identifier),
          lastSeconds: lastSeconds
        )
      }
    )
  }

  /// Stamps the endpoint delivery on the newest frame of the controller attached as `token`; a
  /// token that no connected controller holds stamps nothing.
  public func endpointDelivered(session token: ControllerSessionToken, at nanoseconds: UInt64) async
  {
    guard let identifier = await connectedIdentifier(for: .session(token)) else { return }
    frameTimings.endpointDelivered(for: identifier, at: nanoseconds)
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

  /// Describes one connected controller, matched by its exact key.
  ///
  /// Output routing calls this per input report, so it builds only the requested description.
  public func deviceDescription(
    for identifier: LogicalControllerID
  ) async -> ConnectedDeviceSnapshot? { await deviceDescription(forPipeline: identifier) }

  private func deviceDescription(
    forPipeline id: LogicalControllerID
  ) async -> ConnectedDeviceSnapshot? {
    // A pipeline is registered only after its DeviceInfo; a missing one is mid-teardown.
    guard let pipeline = pipelines[id], let info = deviceInfos[id] else { return nil }
    guard await pipeline.hasConnectedController(), pipelines[id] === pipeline else { return nil }
    let record = protocolDriverRegistry.runtimeProfile(for: info.binding)
    // A raw-USB pipeline runs on the profile resolved from the device's descriptor.
    let transportProfile =
      info.usbTransportDevice != nil ? pipeline.transportProfile : record?.transportProfile
    let ownership = info.ownershipObservation
    var usbHeld = false
    if info.usbTransportDevice != nil { usbHeld = await pipeline.usbOwnedByAnotherClient }
    // A HID key carries an interface only for a protocol role; show the observed one for all.
    let observedInterface: UInt8? =
      if case .hid = info.discoverySource {
        info.physicalDevice?.interfaces?.first?.interfaceNumber
      } else { id.address?.interfaceNumber }
    return ConnectedDeviceSnapshot(
      logicalControllerID: id,
      sessionToken: info.sessionToken,
      portKey: ControllerPortKey.of(id, installationKey: installationKey),
      name: info.name,
      vendorID: id.model.vendorID,
      productID: id.model.productID,
      protocolBinding: info.binding.id,
      connection: info.connection,
      interfaceNumber: observedInterface,
      discoverySource: info.discoverySource.kind,
      physicalOwnership: ownership,
      hidInputOwnership: usbHeld ? .ownedByAnotherClient : info.hidInputOwnership,
      inputOwner: usbHeld ? await pipeline.usbExclusiveOwner : nil,
      duplicateExposureRisk: info.duplicateExposureRisk,
      serialNumber: info.serialNumber,
      parameters: record?.parameters.entries ?? [],
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
      physicalOutputOwner: pipeline.macOSOwnedOutput == nil ? .ojd : .system,
      recordServer: record?.server ?? .system,
      recordAccessRoute: record?.accessRoute ?? .system,
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
  public func connectedLogicalControllerIDs() async -> [LogicalControllerID] {
    var identifiers: [LogicalControllerID] = []
    for (identifier, pipeline) in pipelines {
      if await pipeline.hasConnectedController(), pipelines[identifier] === pipeline {
        identifiers.append(identifier)
      }
    }
    return identifiers
  }

  /// Returns controllers whose sessions can currently publish virtual output.
  public func activeLogicalControllerIDs() async -> [LogicalControllerID] {
    var identifiers: [LogicalControllerID] = []
    for identifier in await connectedLogicalControllerIDs()
    where await pipelines[identifier]?.controllerSessionState() == .active {
      identifiers.append(identifier)
    }
    return identifiers
  }
}
