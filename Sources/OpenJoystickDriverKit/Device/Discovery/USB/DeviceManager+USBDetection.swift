import Foundation

/// The result of admitting one raw-USB service, which decides whether the poll acknowledges it.
enum USBDeviceHandlingOutcome: Equatable {
  /// The service started a pipeline for every role; the identifiers are in slot order.
  case claimed([LogicalControllerID])
  /// The service is left unclaimed and acknowledged, so the poll does not read it again.
  case ignored
  /// The service stays unacknowledged, so the next poll admits it again.
  case retry
}

/// Why a poll of the USB provider failed.
enum USBEnumerationFailure: Equatable, Sendable {
  /// The provider threw a ``USBTransportError``.
  case transport(USBTransportError)
  /// The provider threw another error, described as text.
  case provider(String)

  /// The failure as log text.
  var description: String {
    switch self {
    case .transport(let error): String(reflecting: error)
    case .provider(let detail): detail
    }
  }
}

/// The result of one poll of the USB provider.
enum USBEnumerationPoll: Sendable {
  /// The provider listed these devices.
  case available([USBTransportDevice])
  /// The poll failed.
  case failed(USBEnumerationFailure)
}

/// A change that a poll shows against the acknowledged devices.
enum USBEnumerationEvent: Equatable, Sendable {
  /// A service that is not acknowledged is present.
  case attached(USBTransportDevice)
  /// An acknowledged service is gone or differs from its acknowledged snapshot.
  case detached(USBTransportDevice)
  /// The poll failed.
  case accessFailure(USBEnumerationFailure)
}

/// Lists the provider's devices once and folds a thrown error into a failed poll.
func pollUSBEnumeration(from provider: any USBTransportProvider) async -> USBEnumerationPoll {
  do { return .available(try await provider.devices()) } catch let error as USBTransportError {
    return .failed(.transport(error))
  } catch { return .failed(.provider(String(reflecting: error))) }
}

/// Tracks the raw-USB services that detection has acknowledged and turns polls into attach and
/// detach events.
struct USBEnumerationTracker {
  /// The acknowledged services, by service address.
  private(set) var acknowledgedDevices: [ControllerConnectionAddress: USBTransportDevice] = [:]

  /// Marks `device` as handled, so later polls do not attach it again.
  mutating func acknowledge(_ device: USBTransportDevice) {
    acknowledgedDevices[device.serviceAddress] = device
  }

  /// Forgets a device's acknowledgement without a detach, so the next poll attaches it again.
  mutating func unacknowledge(_ device: USBTransportDevice) {
    acknowledgedDevices.removeValue(forKey: device.serviceAddress)
  }

  /// The attach and detach events that `poll` shows against the acknowledged devices.
  ///
  /// A service that differs from its acknowledged snapshot detaches and then attaches again. A
  /// failed poll yields one access failure.
  mutating func events(for poll: USBEnumerationPoll) -> [USBEnumerationEvent] {
    guard case .available(let devices) = poll else {
      guard case .failed(let failure) = poll else { return [] }
      return [.accessFailure(failure)]
    }

    var currentDevices: [ControllerConnectionAddress: USBTransportDevice] = [:]
    for device in devices { currentDevices[device.serviceAddress] = device }

    var events: [USBEnumerationEvent] = []
    for identity in acknowledgedDevices.keys.sorted() {
      guard let previous = acknowledgedDevices[identity] else { continue }
      guard let current = currentDevices[identity] else {
        acknowledgedDevices.removeValue(forKey: identity)
        events.append(.detached(previous))
        continue
      }
      if current != previous {
        acknowledgedDevices.removeValue(forKey: identity)
        events.append(.detached(previous))
      }
    }

    for identity in currentDevices.keys.sorted()
    where acknowledgedDevices[identity] == nil {
      if let device = currentDevices[identity] { events.append(.attached(device)) }
    }
    return events
  }
}

extension DeviceManager {
  /// Whether a detection run that started at `generation` keeps going: the manager is not stopping,
  /// the lifecycle generation is unchanged and the task is not cancelled.
  func isCurrentUSBDetection(_ generation: UInt64) -> Bool {
    !isStopping && lifecycleGeneration == generation && !Task.isCancelled
  }

  // MARK: - Raw USB detection

  /// Polls the USB transport provider and admits, removes and re-admits raw-USB services until the
  /// manager stops or its lifecycle generation changes.
  ///
  /// A service stays unacknowledged until its admission settles, so the next poll retries it.
  /// Record reloads that wait on this run resume when it ends.
  func runUSBDetection() async {
    defer { resumeRecordReloadWaiters() }
    guard !isStopping, let provider = usbTransportProvider else { return }
    let generation = lifecycleGeneration
    print("[DeviceManager] Raw USB detection started")

    var enumeration = USBEnumerationTracker()
    var serviceToIdentifiers: [ControllerConnectionAddress: [LogicalControllerID]] = [:]

    while isCurrentUSBDetection(generation) {
      await reloadPendingRecords(in: &enumeration, serviceToIdentifiers: &serviceToIdentifiers)
      resumeRecordReloadWaiters()
      guard isCurrentUSBDetection(generation) else { return }
      let poll = await pollUSBEnumeration(from: provider)
      guard isCurrentUSBDetection(generation) else { return }
      let events = enumeration.events(for: poll)
      for event in events {
        guard isCurrentUSBDetection(generation) else { return }
        switch event {
        case .accessFailure(let failure):
          print("[DeviceManager] Raw USB discovery failed: \(failure.description)")
        case .detached(let device):
          await removeUSBDevice(device, serviceToIdentifiers: &serviceToIdentifiers)
          guard isCurrentUSBDetection(generation) else { return }
        case .attached(let device):
          let outcome = await handleUSBDeviceAdded(
            device,
            provider: provider,
            expectedLifecycleGeneration: generation
          )
          guard isCurrentUSBDetection(generation) else { return }
          switch outcome {
          case .claimed(let identifiers):
            serviceToIdentifiers[device.serviceAddress] = identifiers
            guard identifiers.allSatisfy({ isRunningUSBRole($0, of: device) }) else {
              // A role ended during admission. Tear down the survivors and keep the service
              // unacknowledged, so the next poll admits the whole device again.
              await removeUSBDevice(device, serviceToIdentifiers: &serviceToIdentifiers)
              guard isCurrentUSBDetection(generation) else { return }
              continue
            }
            enumeration.acknowledge(device)
          case .ignored: enumeration.acknowledge(device)
          case .retry:
            // Keep the service unacknowledged so the next poll retries it.
            break
          }
        }
      }
      await restoreYieldedHIDRoutes()
      releaseNativeShadowedUSBServices(in: &enumeration)
      await releaseHeldUSBServices(in: &enumeration, provider: provider, generation: generation)
      guard isCurrentUSBDetection(generation) else { return }
      if case .available(let devices) = poll { pruneUSBConfigurationReadFailures(keeping: devices) }
      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  /// Removes each acknowledged service of a model in `pendingRecordReloads` and leaves it
  /// unacknowledged, so the poll that follows admits it with the current records.
  ///
  /// The model's HID connections are admitted again in between, so each route is chosen again. A
  /// removal keeps the user's suspension.
  private func reloadPendingRecords(
    in enumeration: inout USBEnumerationTracker,
    serviceToIdentifiers: inout [ControllerConnectionAddress: [LogicalControllerID]]
  ) async {
    guard !pendingRecordReloads.isEmpty else { return }
    let changed = pendingRecordReloads
    pendingRecordReloads = []
    let devices = enumeration.acknowledgedDevices.values.filter {
      changed.contains(ControllerModelID(vendorID: $0.vendorID, productID: $0.productID))
    }
    for device in devices {
      let suspended = suspendedControllerIdentities.intersection(
        serviceToIdentifiers[device.serviceAddress] ?? []
      )
      await removeUSBDevice(device, serviceToIdentifiers: &serviceToIdentifiers)
      suspendedControllerIdentities.formUnion(suspended)
      enumeration.unacknowledge(device)
    }
    await readmitHIDConnections(changing: changed)
  }

  /// Resumes every ``reloadControllerRecords(changing:)`` call that waits for raw-USB detection.
  private func resumeRecordReloadWaiters() {
    let waiters = recordReloadWaiters
    recordReloadWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  /// Tears down every role of a detached service in one pass: all roles leave the inventory
  /// before any pipeline is awaited, so losing the device is atomic for its slots.
  private func removeUSBDevice(
    _ device: USBTransportDevice,
    serviceToIdentifiers: inout [ControllerConnectionAddress: [LogicalControllerID]]
  ) async {
    clearUnboundDevice(.usb(device.serviceAddress))
    nativeShadowedUSBServices.removeValue(forKey: device.serviceAddress)
    heldUSBServices.removeValue(forKey: device.serviceAddress)
    usbConfigurationReadFailures.removeValue(forKey: device.serviceAddress)
    let identifiers = (serviceToIdentifiers.removeValue(forKey: device.serviceAddress) ?? [])
      .filter { isRunningUSBRole($0, of: device) }
    guard !identifiers.isEmpty else { return }
    let removed = identifiers.compactMap(removeUSBRole)
    // A physical disconnect ends the user's suspension; the next connection starts active.
    suspendedControllerIdentities.subtract(identifiers)
    notifyServiceStatusChanged()
    for pipeline in removed { await pipeline.stop() }
    await reconcileUnboundHIDClaims()
    print("[DeviceManager] USB device removed: \(identifiers)")
  }

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
    guard isCurrentUSBDetection(generation) else { return .retry }
    let (classification, observed) = await classifyUSBDevice(device, provider: provider)
    guard isCurrentUSBDetection(generation) else { return .retry }
    let interfaces = observed.interfaces ?? []
    let binding: ProtocolBinding
    switch classification {
    case .unsupported(let reason, let rejected):
      recordUnboundUSBDevice(
        device,
        reason: reason,
        rejectedCandidates: rejected.map { [$0] } ?? [],
        interfaces: interfaces
      )
      return .ignored
    case .conflict(let reason, let candidates):
      recordUnboundUSBDevice(
        device,
        reason: reason,
        rejectedCandidates: candidates.map {
          ProtocolBindingResult.RejectedCandidate(protocolID: $0, reason: reason)
        },
        interfaces: interfaces
      )
      return .ignored
    case .bound(let bound): binding = bound
    }
    guard
      let configuredProfile = protocolDriverRegistry.runtimeProfile(for: binding)?.transportProfile
    else {
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
      return .ignored
    }

    // Resolution can move the claimed interface, so this early check keys on the configured one
    // and the check after resolution is authoritative.
    let configuredIdentifier = Self.usbIdentifier(for: device, claiming: configuredProfile)
    guard !deferToNativeHID(device, identifier: configuredIdentifier) else { return .ignored }
    guard
      !hasUSBPipelineConflict(
        for: configuredIdentifier,
        service: device.serviceAddress,
        yieldingHID: true
      )
    else {
      print("[DeviceManager] Pipeline already exists for \(configuredIdentifier)")
      return .retry
    }

    let passiveResolution = await provider.resolveTransport(
      for: device,
      configured: configuredProfile
    )
    guard isCurrentUSBDetection(generation) else { return .retry }
    let resolution: USBTransportResolution
    do {
      resolution = try await provider.resolveUSBConfiguration(device, passive: passiveResolution)
    } catch {
      guard isCurrentUSBDetection(generation) else { return .retry }
      return await handleUSBConfigurationReadFailure(
        error,
        device: device,
        provider: provider,
        interfaces: passiveResolution.physicalDevice?.interfaces ?? interfaces,
        generation: generation
      )
    }
    guard isCurrentUSBDetection(generation) else { return .retry }
    usbConfigurationReadFailures.removeValue(forKey: device.serviceAddress)

    // Revalidate the service after the suspension. A removed/replaced service
    // must not be acknowledged from the earlier device snapshot.
    let currentDevices = try? await provider.devices()
    guard isCurrentUSBDetection(generation),
      currentDevices?.contains(where: {
        $0.serviceAddress == device.serviceAddress && $0 == device
      }) == true
    else { return .retry }

    // Descriptor facts are retained only when they identify this exact
    // enumerated service. A provider without passive observations returns nil.
    if let physicalDevice = resolution.physicalDevice,
      physicalDevice.serviceAddress != device.serviceAddress
    {
      return .retry
    }

    // Descriptor resolution suspends the actor. The device may have been
    // replaced or exposed through another route while it was suspended.
    guard isCurrentUSBDetection(generation) else { return .retry }
    // Every role is checked and built before any pipeline exists, so a conflict or a failed
    // contract leaves no partial admission.
    var roles: [USBRoleAdmission] = []
    let roleResolutions = protocolDriverRegistry.roleProfiles(for: binding, resolution: resolution)
    for (slotOrdinal, role) in roleResolutions.enumerated() {
      let identifier = Self.usbIdentifier(for: device, claiming: role.profile)
      guard !deferToNativeHID(device, identifier: identifier) else { return .ignored }
      guard
        !hasUSBPipelineConflict(for: identifier, service: device.serviceAddress, yieldingHID: true)
      else {
        print("[DeviceManager] Pipeline already exists for \(identifier)")
        return .retry
      }
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
        return .ignored
      }
    }
    // Every role is admitted, so the HID route of this controller yields to raw USB now.
    if let first = roles.first { await yieldHIDPipelines(to: first.identifier) }
    return await startUSBRoles(
      roles,
      of: device,
      binding: binding,
      provider: provider,
      generation: generation
    )
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

  /// Records a raw-USB service as unbound for `reason`.
  private func recordUnboundUSBDevice(
    _ device: USBTransportDevice,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [PhysicalInterfaceSignature]
  ) {
    recordUnboundDevice(
      .usb(device.serviceAddress),
      vendorID: device.vendorID,
      productID: device.productID,
      connection: "USB",
      backend: DeviceAccessBackend(route: device.route),
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: interfaces
    )
  }
}
