import Foundation

/// The outcome that ends admission of a raw-USB service before its roles start.
private struct USBAdmissionStop: Error {
  let outcome: USBDeviceHandlingOutcome

  static let retry = Self(outcome: .retry)
  static let ignored = Self(outcome: .ignored)
}

extension DeviceManager {
  /// Admits one attached raw-USB service: classifies it, resolves its transport, checks for
  /// conflicts and starts a pipeline for each of its roles.
  ///
  /// - Parameters:
  ///   - device: The enumerated service.
  ///   - provider: The provider that enumerated it.
  ///   - expectedLifecycleGeneration: The lifecycle generation the caller's detection run started
  ///     under; the current generation when nil.
  /// - Returns: Whether the service started, stays unclaimed, or must be admitted again by the next
  ///   poll.
  @discardableResult
  func handleUSBDeviceAdded(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider,
    expectedLifecycleGeneration: UInt64? = nil
  ) async -> USBDeviceHandlingOutcome {
    let generation = expectedLifecycleGeneration ?? lifecycleGeneration
    do throws(USBAdmissionStop) {
      try requireCurrentUSBDetection(generation)
      let (classification, observed) = await classifyUSBDevice(device, provider: provider)
      try requireCurrentUSBDetection(generation)
      let interfaces = observed.interfaces ?? []
      let binding = try boundUSBBinding(classification, of: device, interfaces: interfaces)
      let configuredProfile = try configuredUSBProfile(
        for: binding,
        of: device,
        interfaces: interfaces
      )
      // Resolution can move the claimed interface, so this early check keys on the configured one
      // and the check after resolution is authoritative.
      try requireUnclaimedUSBRoute(
        device,
        identifier: Self.usbIdentifier(for: device, claiming: configuredProfile)
      )
      let resolution = try await resolveUSBTransport(
        device,
        provider: provider,
        configured: configuredProfile,
        interfaces: interfaces,
        generation: generation
      )
      let roles = try admitUSBRoles(
        of: device,
        binding: binding,
        resolution: resolution,
        interfaces: interfaces
      )
      // Every role is admitted, so the HID route of this controller yields to raw USB now.
      if let first = roles.first { await yieldHIDPipelines(to: first.identifier) }
      return await startUSBRoles(
        roles,
        of: device,
        binding: binding,
        provider: provider,
        generation: generation
      )
    } catch {
      return error.outcome
    }
  }

  /// Stops admission for a retry when the detection run of `generation` is no longer current.
  private func requireCurrentUSBDetection(_ generation: UInt64) throws(USBAdmissionStop) {
    guard isCurrentUSBDetection(generation) else { throw USBAdmissionStop.retry }
  }

  /// Returns the binding of `classification`, or records the service as unbound and stops.
  private func boundUSBBinding(
    _ classification: ProtocolClassification,
    of device: USBTransportDevice,
    interfaces: [PhysicalInterfaceSignature]
  ) throws(USBAdmissionStop) -> ProtocolBinding {
    switch classification {
    case .unsupported(let reason, let rejected):
      recordUnboundUSBDevice(
        device,
        reason: reason,
        rejectedCandidates: rejected.map { [$0] } ?? [],
        interfaces: interfaces
      )
    case .conflict(let reason, let candidates):
      recordUnboundUSBDevice(
        device,
        reason: reason,
        rejectedCandidates: candidates.map {
          ProtocolBindingResult.RejectedCandidate(protocolID: $0, reason: reason)
        },
        interfaces: interfaces
      )
    case .bound(let binding): return binding
    }
    throw USBAdmissionStop.ignored
  }

  /// Returns the transport profile the runtime profile of `binding` configures, or records the
  /// service as unbound and stops.
  private func configuredUSBProfile(
    for binding: ProtocolBinding,
    of device: USBTransportDevice,
    interfaces: [PhysicalInterfaceSignature]
  ) throws(USBAdmissionStop) -> DeviceTransportProfile {
    if let profile = protocolDriverRegistry.runtimeProfile(for: binding)?.transportProfile {
      return profile
    }
    // Only a record-less `HIDDescriptor` binding has no runtime profile; that family is driven
    // through IOHID, never raw USB.
    recordUnboundUSBDevice(
      device,
      reason: .unsupportedTransportVariant,
      rejectedCandidates: [
        ProtocolBindingResult.RejectedCandidate(
          protocolID: binding.protocolID,
          reason: .unsupportedTransportVariant
        )
      ],
      interfaces: interfaces
    )
    throw USBAdmissionStop.ignored
  }

  /// Stops admission when native HID serves `identifier`, or for a retry when another pipeline
  /// holds it.
  private func requireUnclaimedUSBRoute(
    _ device: USBTransportDevice,
    identifier: LogicalControllerID
  ) throws(USBAdmissionStop) {
    guard !deferToNativeHID(device, identifier: identifier) else {
      throw USBAdmissionStop.ignored
    }
    guard
      !hasUSBPipelineConflict(for: identifier, service: device.serviceAddress, yieldingHID: true)
    else {
      print("[DeviceManager] Pipeline already exists for \(identifier)")
      throw USBAdmissionStop.retry
    }
  }

  /// Resolves the transport and USB configuration of `device`, and stops for a retry when the
  /// service changed or the detection run ended while resolution suspended.
  private func resolveUSBTransport(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider,
    configured: DeviceTransportProfile,
    interfaces: [PhysicalInterfaceSignature],
    generation: UInt64
  ) async throws(USBAdmissionStop) -> USBTransportResolution {
    let passiveResolution = await provider.resolveTransport(for: device, configured: configured)
    try requireCurrentUSBDetection(generation)
    let resolution: USBTransportResolution
    do {
      resolution = try await provider.resolveUSBConfiguration(device, passive: passiveResolution)
    } catch {
      try requireCurrentUSBDetection(generation)
      throw USBAdmissionStop(
        outcome: await handleUSBConfigurationReadFailure(
          error,
          device: device,
          provider: provider,
          interfaces: passiveResolution.physicalDevice?.interfaces ?? interfaces,
          generation: generation
        )
      )
    }
    try requireCurrentUSBDetection(generation)
    usbConfigurationReadFailures.removeValue(forKey: device.serviceAddress)

    // Revalidate the service after the suspension. A removed/replaced service
    // must not be acknowledged from the earlier device snapshot.
    let currentDevices = try? await provider.devices()
    try requireCurrentUSBDetection(generation)
    guard
      currentDevices?.contains(where: {
        $0.serviceAddress == device.serviceAddress && $0 == device
      }) == true
    else { throw USBAdmissionStop.retry }

    // Descriptor facts are retained only when they identify this exact
    // enumerated service. A provider without passive observations returns nil.
    if let physicalDevice = resolution.physicalDevice,
      physicalDevice.serviceAddress != device.serviceAddress
    {
      throw USBAdmissionStop.retry
    }

    // Descriptor resolution suspends the actor. The device may have been
    // replaced or exposed through another route while it was suspended.
    try requireCurrentUSBDetection(generation)
    return resolution
  }

  /// Checks and builds every role of `device` before any pipeline exists, so a conflict or a
  /// failed contract leaves no partial admission.
  private func admitUSBRoles(
    of device: USBTransportDevice,
    binding: ProtocolBinding,
    resolution: USBTransportResolution,
    interfaces: [PhysicalInterfaceSignature]
  ) throws(USBAdmissionStop) -> [USBRoleAdmission] {
    var roles: [USBRoleAdmission] = []
    let roleResolutions = protocolDriverRegistry.roleProfiles(for: binding, resolution: resolution)
    for (slotOrdinal, role) in roleResolutions.enumerated() {
      let identifier = Self.usbIdentifier(for: device, claiming: role.profile)
      try requireUnclaimedUSBRoute(device, identifier: identifier)
      switch protocolDriverRegistry.makeDriver(
        for: binding,
        model: identifier.model,
        claimed: role,
        slotOrdinal: slotOrdinal
      ) {
      case .success:
        roles.append(
          USBRoleAdmission(identifier: identifier, resolution: role, slotOrdinal: slotOrdinal)
        )
      case .failure(let reason):
        recordUnboundUSBDevice(
          device,
          reason: reason,
          rejectedCandidates: [
            ProtocolBindingResult.RejectedCandidate(
              protocolID: binding.protocolID,
              reason: reason,
              catalogRecordID: binding.record?.recordID
            )
          ],
          // A catalogued model classified on identity alone; resolution observed its interfaces.
          interfaces: resolution.physicalDevice?.interfaces ?? interfaces
        )
        throw USBAdmissionStop.ignored
      }
    }
    return roles
  }

  /// A catalogued model classifies on its identity, which is all its raw-USB row reads, and runs
  /// the mode its record's match keys select from the passive facts of the enumerated device.
  ///
  /// An uncatalogued model classifies on its passive facts, so an interface signature can bind it.
  /// Returns the classification with the observation it read.
  private func classifyUSBDevice(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider
  ) async -> (ProtocolClassification, PhysicalDevice) {
    let backend = DeviceAccessBackend(route: device.route)
    let identity = PhysicalDevice(vendorID: device.vendorID, productID: device.productID)
    let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    guard let record = protocolDriverRegistry.record(for: model) else {
      guard let observed = await provider.physicalDeviceObservation(for: device) else {
        return (protocolDriverRegistry.classify(identity, backend: backend), identity)
      }
      return (protocolDriverRegistry.classify(observed, backend: backend), observed)
    }
    guard !record.modes.isEmpty,
      let observed = await provider.physicalDeviceObservation(for: device)
    else { return (protocolDriverRegistry.classify(identity, backend: backend), identity) }
    // A raw-USB route has no feature-report read, so a mode with a probe never holds.
    let selection = await protocolDriverRegistry.selectMode(
      of: model,
      backend: backend,
      reader: UnreadableModeProbeReader(),
      device: observed
    )
    return (
      protocolDriverRegistry.classify(identity, backend: backend, modeID: selection.modeID),
      observed
    )
  }
}
