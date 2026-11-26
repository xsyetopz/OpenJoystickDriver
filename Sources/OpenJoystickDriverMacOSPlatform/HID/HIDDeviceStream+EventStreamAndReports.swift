import Foundation
import GameController
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

extension HIDDeviceStream {
  /// Returns a live stream of HID device events (connect, disconnect, input report).
  ///
  /// Only one stream can be active at a time. The stream ends when its
  /// consuming task is cancelled. Runs on main, where IOKit delivers every callback, so admission
  /// of present devices never races the matching, removal, and input callbacks.
  func deviceEvents() -> AsyncStream<HIDDeviceEvent> {
    dispatchPrecondition(condition: .onQueue(.main))
    if continuation != nil { cleanup() }
    streamGeneration &+= 1
    let generation = streamGeneration
    return AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in
        // Termination can fire on any thread; a newer stream must not be torn down by it.
        DispatchQueue.main.async {
          guard let self, self.streamGeneration == generation else { return }
          self.cleanup()
        }
      }
      self.registerCallbacks()
    }
  }

  /// Returns the connections that the manager currently lists, or nil when there is no manager.
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await MainActor.run { self.currentConnectionSnapshotsOnMainRunLoop() }
  }

  /// Returns the connections that the manager currently lists; runs on the main run loop.
  @MainActor
  private func currentConnectionSnapshotsOnMainRunLoop() -> [HIDDeviceConnectionSnapshot]? {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      return nil
    }
    let presentDeviceIDs = Set(devices.map(trackingID(for:)))
    let trackedConnections = seizeLock.withLock { connectionsByDeviceID }
    var ownershipByLocation: [UInt32: HIDInputOwnership] = [:]
    for connection in trackedConnections.values {
      ownershipByLocation[connection.ioKitLocationID] = eventAdapter.ownership(
        locationID: connection.ioKitLocationID
      )
    }
    return HIDDeviceConnectionSnapshot.reconcile(
      trackedConnections: trackedConnections,
      presentDeviceIDs: presentDeviceIDs,
      ownershipByLocation: ownershipByLocation
    )
  }

  // MARK: - Callback registration

  /// The main run loop mode set the HID manager is scheduled in.
  ///
  /// While a menu or another modal loop tracks events, the main run loop leaves the default mode,
  /// so a default-mode manager would deliver no input and each controller with an input liveness
  /// timeout would read as stale.
  static var runLoopMode: CFRunLoopMode { .commonModes }

  /// Registers IOKit callbacks for device matching and removal on the main run loop, then admits
  /// the devices already present.
  ///
  /// The manager is never opened. `IOHIDManagerOpen` opens every matched device object, which
  /// includes OJD's own virtual gamepads (they match the GamePad usage, and IOKit matching
  /// ignores negative property keys) and a second object for any service that satisfies more
  /// than one matching dictionary. `handleDeviceAdded` opens only admitted devices.
  private func registerCallbacks() {
    // The service is never frontmost, and the controller list was measured with this set.
    GCController.shouldMonitorBackgroundEvents = true
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    self.manager = manager
    IOHIDManagerSetDeviceMatchingMultiple(manager, currentDeviceMatching())
    let context = unsafe Unmanaged.passUnretained(self).toOpaque()
    unsafe IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
    unsafe IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), Self.runLoopMode.rawValue)
    // Admit the devices already present in case matching callbacks do not report them.
    // Admission is safe to repeat per device and service.
    let present = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    for device in present {
      if let failure = handleDeviceAdded(device, failingOnAccessDenial: true) {
        continuation?.yield(failure)
        cleanup()
        return
      }
    }
  }

  /// Maps a denied shared open of an already-present device to a stream-level access failure.
  static func accessFailure(forInitialOpenResult result: IOReturn) -> HIDDeviceEvent? {
    guard result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged else { return nil }
    return .accessFailure(.init(ioReturn: result))
  }

  /// Unschedules the HID manager from the run loop, closes the devices this stream opened, and
  /// finishes the async stream.
  ///
  /// Runs on main.
  func cleanup() {
    guard let continuation else { return }
    self.continuation = nil
    if let manager {
      IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
      IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
      IOHIDManagerUnscheduleFromRunLoop(
        manager,
        CFRunLoopGetMain(),
        Self.runLoopMode.rawValue
      )
      self.manager = nil
    }
    let sharedOpens = unsafe seizeLock.withLock {
      for devices in seizedByLocation.values {
        for device in devices {
          IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
      }
      seizedByLocation.removeAll()
      releasedByLocation.removeAll()
      closedByLocation.removeAll()
      gameControllerListings.removeAll()
      connectionsByDeviceID.removeAll()
      defer { unsafe sharedOpenByDeviceID.removeAll() }
      return unsafe Array(sharedOpenByDeviceID.values)
    }
    unsafe sharedOpens.forEach(closeSharedOpen)
    eventAdapter.reset()
    continuation.finish()
  }

  /// Sends an output report to the devices at `locationID`.
  package func releaseInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    seizeLock.withLock {
      guard let devices = seizedByLocation.removeValue(forKey: locationID), !devices.isEmpty else {
        return .unavailable
      }
      var lastFailure: IOReturn?
      for device in devices {
        let result = HIDInputClaim.release(port: HIDDeviceOpenPort(device: device))
        if result == kIOReturnSuccess {
          sizeReportQueue(device)
        } else {
          lastFailure = result
        }
      }
      if let lastFailure { return .failed(.init(ioReturn: lastFailure)) }
      releasedByLocation[locationID] = devices
      return .released
    }
  }

  /// Seizes again the devices ``releaseInputClaim(locationID:)`` released.
  ///
  /// When one seize is refused, the devices seized so far return to a shared open and the refusal
  /// is the result. A location whose handles ``closeDeviceHandles(locationID:)`` closed stays
  /// closed until ``reopenDeviceHandles(locationID:)``.
  package func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    seizeLock.withLock {
      guard closedByLocation[locationID] == nil,
        let devices = releasedByLocation[locationID], !devices.isEmpty
      else {
        return .unavailable
      }
      var acquired: [IOHIDDevice] = []
      for device in devices {
        let port = HIDDeviceOpenPort(device: device)
        let claim = HIDInputClaim.reclaim(port: port)
        if claim.inputResult == kIOReturnSuccess { sizeReportQueue(device) }
        guard claim.seized else {
          for acquiredDevice in acquired {
            _ = HIDInputClaim.release(port: HIDDeviceOpenPort(device: acquiredDevice))
            sizeReportQueue(acquiredDevice)
          }
          return .failed(.init(ioReturn: claim.seizeResult ?? kIOReturnError))
        }
        acquired.append(device)
      }
      releasedByLocation.removeValue(forKey: locationID)
      seizedByLocation[locationID] = acquired
      return .reacquired
    }
  }

  /// Closes every handle this stream holds on the devices at a location, the seize and the input
  /// open, so another process can open them.
  ///
  /// The share that ``releaseInputClaim(locationID:)`` leaves still blocks a client that seizes,
  /// and a suspended controller needs no input.
  @MainActor
  package func closeDeviceHandles(locationID: UInt32) -> PhysicalHIDClaimResult {
    let seized = seizeLock.withLock { seizedByLocation.removeValue(forKey: locationID) ?? [] }
    let sharedOpens = unsafe seizeLock.withLock { () -> [SharedOpenDevice] in
      let deviceIDs = connectionsByDeviceID.filter { $0.value.ioKitLocationID == locationID }.keys
      return unsafe deviceIDs.compactMap { unsafe sharedOpenByDeviceID.removeValue(forKey: $0) }
    }
    guard unsafe !sharedOpens.isEmpty else { return .unavailable }
    var closed: [ClosedDevice] = []
    for unsafe sharedOpen in unsafe sharedOpens {
      let device = unsafe sharedOpen.device
      let wasSeized = seized.contains { CFEqual($0, device) }
      if wasSeized { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) }
      unsafe closeSharedOpen(sharedOpen)
      closed.append(ClosedDevice(device: device, seized: wasSeized))
    }
    seizeLock.withLock { closedByLocation[locationID] = closed }
    return .released
  }

  /// Opens again the devices ``closeDeviceHandles(locationID:)`` closed, seizing the ones that were
  /// seized.
  ///
  /// A device whose open fails stays closed for the next call, and the failure is the result.
  @MainActor
  package func reopenDeviceHandles(locationID: UInt32) -> PhysicalHIDClaimResult {
    guard let closed = seizeLock.withLock({ closedByLocation.removeValue(forKey: locationID) })
    else { return .unavailable }
    var stillClosed: [ClosedDevice] = []
    var lastFailure: IOReturn?
    for entry in closed {
      let deviceID = trackingID(for: entry.device)
      let claim = HIDInputClaim.admit(
        port: HIDDeviceOpenPort(device: entry.device),
        seize: entry.seized
      )
      if entry.seized {
        record(claim, device: entry.device, deviceID: deviceID, locationID: locationID)
      }
      if claim.inputResult == kIOReturnSuccess {
        attachInput(entry.device, deviceID: deviceID)
      } else {
        stillClosed.append(entry)
        lastFailure = claim.inputResult
      }
    }
    guard let lastFailure else { return .reacquired }
    seizeLock.withLock { closedByLocation[locationID] = stillClosed }
    return .failed(.init(ioReturn: lastFailure))
  }

  /// Re-runs the seize of tracked non-native devices at a location whose earlier seize was
  /// refused or failed, attaches the input of a device that had no shared open, and yields
  /// `.ownershipChanged` when the location's ownership changes.
  @MainActor
  package func retryInputClaim(locationID: UInt32) {
    guard !eventAdapter.hasNativeDevice(locationID: locationID) else { return }
    let (tracked, sharedOpenIDs) = seizeLock.withLock {
      () -> ([UInt64: HIDDeviceConnection], Set<UInt64>) in
      guard releasedByLocation[locationID]?.isEmpty ?? true, closedByLocation[locationID] == nil
      else { return ([:], []) }
      return unsafe (connectionsByDeviceID, Set(sharedOpenByDeviceID.keys))
    }
    let candidateIDs = Self.inputClaimRetryCandidates(tracked: tracked, locationID: locationID) {
      eventAdapter.ownership(deviceID: $0)
    }
    guard !candidateIDs.isEmpty, let manager,
      let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
    else { return }
    let devicesByID = Dictionary(devices.map { (trackingID(for: $0), $0) }) { first, _ in first }
    let before = eventAdapter.ownership(locationID: locationID)
    for deviceID in candidateIDs {
      guard let device = devicesByID[deviceID] else { continue }
      let claim = HIDInputClaim.reclaim(port: HIDDeviceOpenPort(device: device))
      record(claim, device: device, deviceID: deviceID, locationID: locationID)
      guard claim.inputResult == kIOReturnSuccess else { continue }
      if sharedOpenIDs.contains(deviceID) {
        sizeReportQueue(device)
      } else {
        attachInput(device, deviceID: deviceID)
      }
    }
    let after = eventAdapter.ownership(locationID: locationID)
    if after != before {
      continuation?.yield(
        .ownershipChanged(
          address: .ioKit(locationID: locationID, interfaceNumber: nil),
          ownership: after
        )
      )
    }
  }

  /// The tracked devices at `locationID` whose seize was refused or failed, in ID order.
  ///
  /// Each is retried whether or not it has a shared open: while another client seizes a device,
  /// macOS refuses the shared open too.
  static func inputClaimRetryCandidates(
    tracked: [UInt64: HIDDeviceConnection],
    locationID: UInt32,
    ownership: (UInt64) -> HIDInputOwnership?
  ) -> [UInt64] {
    tracked.compactMap { deviceID, connection -> UInt64? in
      guard connection.ioKitLocationID == locationID else { return nil }
      switch ownership(deviceID) {
      case .ownedByAnotherClient, .acquisitionFailed: return deviceID
      default: return nil
      }
    }.sorted()
  }
  // MARK: - Event handlers
}
