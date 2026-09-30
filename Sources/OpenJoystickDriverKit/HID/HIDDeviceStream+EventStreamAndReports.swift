import Foundation
import IOKit
import IOKit.hid

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

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await MainActor.run { self.currentConnectionSnapshotsOnMainRunLoop() }
  }

  @MainActor
  private func currentConnectionSnapshotsOnMainRunLoop() -> [HIDDeviceConnectionSnapshot]? {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      return nil
    }
    let presentDeviceIDs = Set(devices.map(trackingID(for:)))
    let trackedConnections = seizeLock.withLock { connectionsByDeviceID }
    var ownershipByLocation: [UInt32: HIDInputOwnership] = [:]
    for connection in trackedConnections.values {
      ownershipByLocation[connection.routingLocationID] = eventAdapter.ownership(
        locationID: connection.routingLocationID
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
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    self.manager = manager
    IOHIDManagerSetDeviceMatchingMultiple(manager, deviceMatching)
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
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
    return .accessFailure(.ioReturn(result))
  }

  /// Unschedules the HID manager from the run loop, closes the devices this stream opened, and
  /// finishes the async stream. Runs on main.
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
    let sharedOpens = seizeLock.withLock {
      for devices in seizedByLocation.values {
        for device in devices {
          IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
      }
      seizedByLocation.removeAll()
      releasedByLocation.removeAll()
      connectionsByDeviceID.removeAll()
      defer { sharedOpenByDeviceID.removeAll() }
      return Array(sharedOpenByDeviceID.values)
    }
    sharedOpens.forEach(closeSharedOpen)
    eventAdapter.reset()
    continuation.finish()
  }

  public func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    setReport(locationID: locationID, report: report, type: kIOHIDReportTypeOutput, label: "Output")
  }

  public func setOutputReport(
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

  public func setFeatureReport(
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

  public func setFeatureReport(
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

  public func getFeatureReport(
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
        return IOHIDDeviceGetReport(
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
        + " report=0x\(String(format: "%02X", request.reportID)) kr=\(lastResult)"
    )
    return .failed(.ioReturn(lastResult))
  }

  public func releaseInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    seizeLock.withLock {
      guard let devices = seizedByLocation.removeValue(forKey: locationID), !devices.isEmpty else {
        return .unavailable
      }
      var lastFailure: IOReturn?
      for device in devices {
        let result = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result != kIOReturnSuccess { lastFailure = result }
      }
      if let lastFailure { return .failed(.ioReturn(lastFailure)) }
      releasedByLocation[locationID] = devices
      return .released
    }
  }

  public func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    seizeLock.withLock {
      guard let devices = releasedByLocation[locationID], !devices.isEmpty else {
        return .unavailable
      }
      var acquired: [IOHIDDevice] = []
      for device in devices {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
          for acquiredDevice in acquired {
            IOHIDDeviceClose(acquiredDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
          }
          return .failed(.ioReturn(result))
        }
        acquired.append(device)
      }
      releasedByLocation.removeValue(forKey: locationID)
      seizedByLocation[locationID] = acquired
      return .reacquired
    }
  }

  /// Re-runs the seize of tracked non-native devices at a location whose earlier seize was
  /// refused or failed, and yields `.ownershipChanged` when the location's ownership changes.
  public func retryInputClaim(locationID: UInt32) {
    guard !eventAdapter.hasNativeDevice(locationID: locationID) else { return }
    let candidates: [(deviceID: UInt64, device: IOHIDDevice)] = seizeLock.withLock {
      guard releasedByLocation[locationID]?.isEmpty ?? true else { return [] }
      return sharedOpenByDeviceID.compactMap { deviceID, sharedOpen in
        connectionsByDeviceID[deviceID]?.routingLocationID == locationID
          ? (deviceID, sharedOpen.device) : nil
      }
    }
    let before = eventAdapter.ownership(locationID: locationID)
    for candidate in candidates {
      switch eventAdapter.ownership(deviceID: candidate.deviceID) {
      case .ownedByAnotherClient, .acquisitionFailed:
        seizeInput(candidate.device, deviceID: candidate.deviceID, locationID: locationID)
      default: continue
      }
    }
    let after = eventAdapter.ownership(locationID: locationID)
    if after != before {
      continuation?.yield(.ownershipChanged(locationID: locationID, ownership: after))
    }
  }

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
        return IOHIDDeviceSetReport(
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
        + " report=0x\(String(format: "%02X", report.reportID)) kr=\(lastResult)"
    )
    return .failed(.ioReturn(lastResult))
  }

  /// Reads a feature report only from the exact connection lifetime, never a sibling at its
  /// location.
  public func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await MainActor.run {
      guard let device = exactDevice(for: connection, type: kIOHIDReportTypeFeature, reads: true)
      else { return .unavailable }
      var bytes = [UInt8](repeating: 0, count: request.length)
      var reportLength = request.length
      let result = bytes.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return IOHIDDeviceGetReport(
          device,
          kIOHIDReportTypeFeature,
          CFIndex(request.reportID),
          baseAddress,
          &reportLength
        )
      }
      guard result == kIOReturnSuccess else { return .failed(.ioReturn(result)) }
      return .success(Data(bytes.prefix(reportLength)))
    }
  }

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
      return IOHIDDeviceSetReport(device, type, CFIndex(report.reportID), baseAddress, reportLength)
    }
    guard result == kIOReturnSuccess else {
      print(
        "[HIDDeviceStream] \(label) report failed for exact connection "
          + "report=0x\(String(format: "%02X", report.reportID)) kr=\(result)"
      )
      return .failed(.ioReturn(result))
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
          return permitted && sharedOpenByDeviceID[deviceID] != nil
        }
        return seizedByLocation[connection.routingLocationID]?.contains(where: {
          CFEqual($0, device)
        }) == true
      })
    else { return nil }
    return device
  }

  // MARK: - Event handlers
}
