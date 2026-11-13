package import Foundation
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
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    // Admit the devices already present in case matching callbacks do not report them.
    // Admission is idempotent per device and service.
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
        CFRunLoopMode.defaultMode.rawValue
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
  package func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    setReport(locationID: locationID, report: report, type: kIOHIDReportTypeOutput, label: "Output")
  }

  /// Sends an output report to the device of `connection`, on the main actor.
  package func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await MainActor.run {
      setReport(
        connection: connection,
        report: report,
        type: kIOHIDReportTypeOutput,
        label: "Output"
      )
    }
  }

  /// Sends a feature report to the devices at `locationID`.
  package func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    setReport(
      locationID: locationID,
      report: report,
      type: kIOHIDReportTypeFeature,
      label: "Feature"
    )
  }

  /// Sends a feature report to the device of `connection`, on the main actor.
  package func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await MainActor.run {
      setReport(
        connection: connection,
        report: report,
        type: kIOHIDReportTypeFeature,
        label: "Feature"
      )
    }
  }

  /// Reads the feature report that `request` names from the devices at `locationID`.
  package func getFeatureReport(
    locationID: UInt32,

    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return .unavailable }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return .unavailable }

    var lastResult = kIOReturnNotFound
    for device in devices {
      var bytes = [UInt8](repeating: 0, count: request.length)

      var reportLength = request.length
      let result = bytes.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return unsafe IOHIDDeviceGetReport(
          device,
          kIOHIDReportTypeFeature,
          CFIndex(request.reportID),
          baseAddress,
          &reportLength
        )
      }
      if result == kIOReturnSuccess { return .success(Data(bytes.prefix(reportLength))) }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] Feature report read failed for loc=\(locationID)"
        + " report=0x\(unsafe String(format: "%02X", request.reportID)) kr=\(lastResult)"
    )
    return .failed(.init(ioReturn: lastResult))
  }

  /// Replaces the seize of each device at a location with a shared open, so another client can
  /// open the devices while input keeps flowing here.
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
  /// is the result.
  package func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    seizeLock.withLock {
      guard let devices = releasedByLocation[locationID], !devices.isEmpty else {
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

  /// Sends `report` of the given IOHID report `type` to the devices at `locationID`.
  ///
  /// `label` names the report type in the failure text. The result is unavailable when the location
  /// has no seized device or does not accept feedback.
  private func setReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport,
    type: IOHIDReportType,
    label: String
  ) -> PhysicalHIDReportResult<Void> {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return .unavailable }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return .unavailable }

    var lastResult = kIOReturnNotFound
    for device in devices {
      var bytes = report.bytes
      let reportLength = bytes.count
      let result = bytes.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return unsafe IOHIDDeviceSetReport(
          device,
          type,
          CFIndex(report.reportID),
          baseAddress,
          reportLength
        )
      }
      if result == kIOReturnSuccess { return .success(()) }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] \(label) report failed for loc=\(locationID)"
        + " report=0x\(unsafe String(format: "%02X", report.reportID)) kr=\(lastResult)"
    )
    return .failed(.init(ioReturn: lastResult))
  }

  /// Reads a feature report only from the exact connection lifetime, never a sibling at its
  /// location.
  ///
  /// It waits for the device on the main actor, as the startup reads always have.
  package func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await MainActor.run {
      guard let device = exactDevice(for: connection, type: kIOHIDReportTypeFeature, reads: true)
      else { return .unavailable }
      return Self.readFeatureReport(device, request: request)
    }
  }

  /// Reads a feature report for a mode probe, off the main actor and bounded by `timeout`.
  ///
  /// While an earlier probe read of the same connection has not returned, it fails with
  /// `kIOReturnBusy` instead of reading.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest,
    timeout: TimeInterval = 2
  ) async -> PhysicalHIDReportResult<Data> {
    let device = await MainActor.run {
      exactDevice(for: connection, type: kIOHIDReportTypeFeature, reads: true).map(
        UncheckedSendableDevice.init
      )
    }
    guard let device else { return .unavailable }
    return await boundedReads.run(key: connection.connectionID, timeout: timeout) {
      Self.readFeatureReport(device.device, request: request)
    }
  }

  /// Reads the feature report that `request` names from `device`.
  private static func readFeatureReport(
    _ device: IOHIDDevice,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    var bytes = [UInt8](repeating: 0, count: request.length)
    var reportLength = request.length
    let result = bytes.withUnsafeMutableBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
      return unsafe IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeFeature,
        CFIndex(request.reportID),
        baseAddress,
        &reportLength
      )
    }
    guard result == kIOReturnSuccess else { return .failed(.init(ioReturn: result)) }
    return .success(Data(bytes.prefix(reportLength)))
  }

  /// Sends `report` of the given IOHID report `type` to the device of `connection`.
  @MainActor
  private func setReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport,
    type: IOHIDReportType,
    label: String
  ) -> PhysicalHIDReportResult<Void> {
    guard let device = exactDevice(for: connection, type: type) else { return .unavailable }
    var bytes = report.bytes
    let reportLength = bytes.count
    let result = bytes.withUnsafeMutableBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
      return unsafe IOHIDDeviceSetReport(
        device,
        type,
        CFIndex(report.reportID),
        baseAddress,
        reportLength
      )
    }
    guard result == kIOReturnSuccess else {
      print(
        "[HIDDeviceStream] \(label) report failed for exact connection "
          + "report=0x\(unsafe String(format: "%02X", report.reportID)) kr=\(result)"
      )
      return .failed(.init(ioReturn: result))
    }
    return .success(())
  }

  /// The device object of an exact connection lifetime that accepts a `type` report, read when
  /// `reads` is set and written otherwise.
  @MainActor
  private func exactDevice(
    for connection: HIDDeviceConnection,
    type: IOHIDReportType,
    reads: Bool = false
  ) -> IOHIDDevice? {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      let deviceID = seizeLock.withLock({
        connectionsByDeviceID.first { $0.value == connection }?.key
      }), let device = devices.first(where: { trackingID(for: $0) == deviceID }),
      eventAdapter.acceptsInput(deviceID: deviceID),
      seizeLock.withLock({
        // A native device is never seized: an output report DeviceManager's native allowance
        // permits, or a feature read it makes, goes through its shared open; every other write
        // needs the seize.
        if connection.physicalDevice.nativePassThrough {
          let permitted = reads ? type == kIOHIDReportTypeFeature : type == kIOHIDReportTypeOutput
          return unsafe permitted && sharedOpenByDeviceID[deviceID] != nil
        }
        return seizedByLocation[connection.ioKitLocationID]?.contains(where: {
          CFEqual($0, device)
        }) == true
      })
    else { return nil }
    return device
  }

  // MARK: - Event handlers
}

/// An `IOHIDDevice` handed to the queue that reads it.
///
/// IOKit device calls are thread-safe.
private struct UncheckedSendableDevice: @unchecked Sendable {
  /// The device, wrapped so that it can cross concurrency domains.
  let device: IOHIDDevice
}
