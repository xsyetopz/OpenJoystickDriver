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

/// A listing of the USB provider that a later poll may reuse.
struct USBEnumerationListing {
  /// The listed devices.
  var devices: [USBTransportDevice]
  /// The provider's change count, read before the listing.
  var changeCount: UInt64
  /// The uptime of the listing, in nanoseconds.
  var listedAt: UInt64
}

/// Returns the devices of `last` when that listing still holds, and else lists the provider's
/// devices and records the listing in `last`.
///
/// A listing holds while the provider reports no change since it, `tracker` acknowledges exactly
/// its devices, and it is younger than `maxAgeNanoseconds`. Listing reads every USB device's
/// registry properties, which a controller-free poll twice a second spent on nothing; the age
/// bound still catches a change the provider does not report, such as an edited record.
func pollUSBEnumeration(
  from provider: any USBTransportProvider,
  tracker: USBEnumerationTracker,
  last: inout USBEnumerationListing?,
  now: UInt64,
  maxAgeNanoseconds: UInt64 = usbEnumerationMaxAgeNanoseconds
) async -> USBEnumerationPoll {
  let changeCount = await provider.enumerationChangeCount
  if let listing = last, let changeCount, listing.changeCount == changeCount,
    now &- listing.listedAt < maxAgeNanoseconds, tracker.agrees(with: listing.devices)
  {
    return .available(listing.devices)
  }
  let poll = await pollUSBEnumeration(from: provider)
  if case .available(let devices) = poll, let changeCount {
    last = USBEnumerationListing(devices: devices, changeCount: changeCount, listedAt: now)
  } else {
    last = nil
  }
  return poll
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

  /// Whether the acknowledged services are exactly `devices`, so that a poll of them yields no
  /// event.
  func agrees(with devices: [USBTransportDevice]) -> Bool {
    devices.count == acknowledgedDevices.count
      && devices.allSatisfy { acknowledgedDevices[$0.serviceAddress] == $0 }
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
    var listing: USBEnumerationListing?

    while isCurrentUSBDetection(generation) {
      // Reloaded records can change which devices the provider lists.
      if await reloadPendingRecords(in: &enumeration, serviceToIdentifiers: &serviceToIdentifiers) {
        listing = nil
      }
      resumeRecordReloadWaiters()
      guard isCurrentUSBDetection(generation) else { return }
      let poll = await pollUSBEnumeration(
        from: provider,
        tracker: enumeration,
        last: &listing,
        now: DispatchTime.now().uptimeNanoseconds
      )
      guard isCurrentUSBDetection(generation) else { return }
      for event in enumeration.events(for: poll) {
        guard isCurrentUSBDetection(generation),
          await applyUSBEvent(
            event,
            provider: provider,
            generation: generation,
            enumeration: &enumeration,
            serviceToIdentifiers: &serviceToIdentifiers
          )
        else { return }
      }
      await restoreYieldedHIDRoutes()
      releaseNativeShadowedUSBServices(in: &enumeration)
      await releaseHeldUSBServices(in: &enumeration, provider: provider, generation: generation)
      guard isCurrentUSBDetection(generation) else { return }
      if case .available(let devices) = poll { pruneUSBConfigurationReadFailures(keeping: devices) }
      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  /// Applies one enumeration event and tells whether the detection run of `generation` goes on.
  ///
  /// A service stays unacknowledged when its admission must be retried or one of its roles ended
  /// during admission, so the next poll admits it again.
  private func applyUSBEvent(
    _ event: USBEnumerationEvent,
    provider: any USBTransportProvider,
    generation: UInt64,
    enumeration: inout USBEnumerationTracker,
    serviceToIdentifiers: inout [ControllerConnectionAddress: [LogicalControllerID]]
  ) async -> Bool {
    switch event {
    case .accessFailure(let failure):
      print("[DeviceManager] Raw USB discovery failed: \(failure.description)")
      return true
    case .detached(let device):
      await removeUSBDevice(device, serviceToIdentifiers: &serviceToIdentifiers)
      return isCurrentUSBDetection(generation)
    case .attached(let device):
      let outcome = await handleUSBDeviceAdded(
        device,
        provider: provider,
        expectedLifecycleGeneration: generation
      )
      guard isCurrentUSBDetection(generation) else { return false }
      switch outcome {
      case .claimed(let identifiers):
        serviceToIdentifiers[device.serviceAddress] = identifiers
        guard identifiers.allSatisfy({ isRunningUSBRole($0, of: device) }) else {
          // A role ended during admission. Tear down the survivors and keep the service
          // unacknowledged, so the next poll admits the whole device again.
          await removeUSBDevice(device, serviceToIdentifiers: &serviceToIdentifiers)
          return isCurrentUSBDetection(generation)
        }
        enumeration.acknowledge(device)
      case .ignored: enumeration.acknowledge(device)
      case .retry: break
      }
      return true
    }
  }

  /// Removes each acknowledged service of a model in `pendingRecordReloads` and leaves it
  /// unacknowledged, so the poll that follows admits it with the current records, and tells
  /// whether any model was pending.
  ///
  /// The model's HID connections are admitted again in between, so each route is chosen again. A
  /// removal keeps the user's suspension.
  private func reloadPendingRecords(
    in enumeration: inout USBEnumerationTracker,
    serviceToIdentifiers: inout [ControllerConnectionAddress: [LogicalControllerID]]
  ) async -> Bool {
    guard !pendingRecordReloads.isEmpty else { return false }
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
    return true
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

  /// Records a raw-USB service as unbound for `reason`, with the interfaces observed.
  func recordUnboundUSBDevice(
    _ device: USBTransportDevice,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate] = [],
    interfaces: [PhysicalInterfaceSignature],
    exclusiveOwner: USBExclusiveOwner? = nil
  ) {
    recordUnboundDevice(
      .usb(device.serviceAddress),
      vendorID: device.vendorID,
      productID: device.productID,
      productName: device.productName,
      connection: "USB",
      backend: DeviceAccessBackend(route: device.route),
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: interfaces,
      exclusiveOwner: exclusiveOwner
    )
  }
}
