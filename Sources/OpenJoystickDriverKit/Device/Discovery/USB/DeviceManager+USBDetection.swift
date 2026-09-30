import Foundation

enum USBDeviceHandlingOutcome: Equatable {
  /// Every role pipeline of the service, in slot order.
  case claimed([DeviceIdentifier])
  case ignored
  case retry
}

enum USBEnumerationFailure: Equatable, Sendable {
  case transport(USBTransportError)
  case provider(String)

  var description: String {
    switch self {
    case .transport(let error): String(reflecting: error)
    case .provider(let detail): detail
    }
  }
}

enum USBEnumerationPoll: Sendable {
  case available([USBTransportDevice])
  case failed(USBEnumerationFailure)
}

enum USBEnumerationEvent: Equatable, Sendable {
  case attached(USBTransportDevice)
  case detached(USBTransportDevice)
  case accessFailure(USBEnumerationFailure)
}

func pollUSBEnumeration(from provider: any USBTransportProvider) async -> USBEnumerationPoll {
  do { return .available(try await provider.devices()) } catch let error as USBTransportError {
    return .failed(.transport(error))
  } catch { return .failed(.provider(String(reflecting: error))) }
}

struct USBEnumerationTracker {
  private(set) var acknowledgedDevices: [USBTransportServiceIdentity: USBTransportDevice] = [:]

  mutating func acknowledge(_ device: USBTransportDevice) {
    acknowledgedDevices[device.serviceIdentity] = device
  }

  /// Forgets a device's acknowledgement without a detach, so the next poll attaches it again.
  mutating func unacknowledge(_ device: USBTransportDevice) {
    acknowledgedDevices.removeValue(forKey: device.serviceIdentity)
  }

  mutating func events(for poll: USBEnumerationPoll) -> [USBEnumerationEvent] {
    guard case .available(let devices) = poll else {
      guard case .failed(let failure) = poll else { return [] }
      return [.accessFailure(failure)]
    }

    var currentDevices: [USBTransportServiceIdentity: USBTransportDevice] = [:]
    for device in devices { currentDevices[device.serviceIdentity] = device }

    var events: [USBEnumerationEvent] = []
    for identity in acknowledgedDevices.keys.sorted(by: Self.precedes) {
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

    for identity in currentDevices.keys.sorted(by: Self.precedes)
    where acknowledgedDevices[identity] == nil {
      if let device = currentDevices[identity] { events.append(.attached(device)) }
    }
    return events
  }

  private static func precedes(
    _ lhs: USBTransportServiceIdentity,
    _ rhs: USBTransportServiceIdentity
  ) -> Bool {
    if lhs.route != rhs.route { return lhs.route.rawValue < rhs.route.rawValue }
    return lhs.serviceID < rhs.serviceID
  }
}

extension DeviceManager {
  func isCurrentUSBDetection(_ generation: UInt64) -> Bool {
    !isStopping && lifecycleGeneration == generation && !Task.isCancelled
  }

  // MARK: - Raw USB detection

  func runUSBDetection() async {
    guard !isStopping, let provider = usbTransportProvider else { return }
    let generation = lifecycleGeneration
    print("[DeviceManager] Raw USB detection started")

    var enumeration = USBEnumerationTracker()
    var serviceToIdentifiers: [USBTransportServiceIdentity: [DeviceIdentifier]] = [:]

    while isCurrentUSBDetection(generation) {
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
            serviceToIdentifiers[device.serviceIdentity] = identifiers
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
      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  /// Tears down every role of a detached service in one pass: all roles leave the inventory
  /// before any pipeline is awaited, so losing the device is atomic for its slots.
  private func removeUSBDevice(
    _ device: USBTransportDevice,
    serviceToIdentifiers: inout [USBTransportServiceIdentity: [DeviceIdentifier]]
  ) async {
    clearUnboundDevice(.usb(device.serviceIdentity))
    nativeShadowedUSBServices.removeValue(forKey: device.serviceIdentity)
    let identifiers = (serviceToIdentifiers.removeValue(forKey: device.serviceIdentity) ?? [])
      .filter { isRunningUSBRole($0, of: device) }
    guard !identifiers.isEmpty else { return }
    let removed = identifiers.compactMap(removeUSBRole)
    // A physical disconnect ends the user's suspension; the next connection starts active.
    suspendedControllerIdentities.subtract(identifiers)
    notifyControllerInventoryChanged()
    for pipeline in removed { await pipeline.stop() }
    await reconcileUnboundHIDClaims()
    print("[DeviceManager] USB device removed: \(identifiers)")
  }

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
      // Only a record-less `hid.descriptor` binding has no runtime profile; that family is driven
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
        service: device.serviceIdentity,
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
    let configuredResolution = await provider.resolveUSBConfiguration(
      device,
      passive: passiveResolution
    )
    guard isCurrentUSBDetection(generation), let resolution = configuredResolution else {
      return .retry
    }

    // Revalidate the service after the suspension. A removed/replaced service
    // must not be acknowledged from the earlier device snapshot.
    let currentDevices = try? await provider.devices()
    guard isCurrentUSBDetection(generation),
      currentDevices?.contains(where: {
        $0.serviceIdentity == device.serviceIdentity && $0 == device
      }) == true
    else { return .retry }

    // Descriptor facts are retained only when they identify this exact
    // enumerated service. A provider without passive observations returns nil.
    if let physicalDevice = resolution.physicalDevice,
      physicalDevice.serviceIdentity != device.serviceIdentity
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
        !hasUSBPipelineConflict(for: identifier, service: device.serviceIdentity, yieldingHID: true)
      else {
        print("[DeviceManager] Pipeline already exists for \(identifier)")
        return .retry
      }
      switch protocolDriverRegistry.makeDriver(
        for: binding,
        identifier: identifier,
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

  /// A catalogued model classifies on its identity, which is all its raw-USB row reads. An
  /// uncatalogued model classifies on its passive facts, so an interface signature can bind it.
  /// Returns the classification with the observation it read.
  private func classifyUSBDevice(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider
  ) async -> (ProtocolClassification, PhysicalDevice) {
    let backend = DeviceAccessBackend(route: device.route)
    let identity = PhysicalDevice(vendorID: device.vendorID, productID: device.productID)
    guard
      protocolDriverRegistry.record(
        for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      ) == nil, let observed = await provider.physicalDeviceObservation(for: device)
    else { return (protocolDriverRegistry.classify(identity, backend: backend), identity) }
    return (protocolDriverRegistry.classify(observed, backend: backend), observed)
  }

  private func recordUnboundUSBDevice(
    _ device: USBTransportDevice,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [PhysicalInterfaceSignature]
  ) {
    recordUnboundDevice(
      .usb(device.serviceIdentity),
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
