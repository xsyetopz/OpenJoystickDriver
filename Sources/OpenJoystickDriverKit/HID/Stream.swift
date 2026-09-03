import Foundation
import IOKit
import IOKit.hid

/// Watches for HID-class game controllers using Apple's IOKit HID framework.
///
/// Creates an `AsyncStream` of device connect, disconnect, and input report
/// events. IOKit delivers callbacks on the main run loop, and this class
/// forwards them into the stream for safe async consumption.
@available(macOS, introduced: 10.15, obsoleted: 15.0)
public final class HIDDeviceStream: @unchecked Sendable {

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - All IOKit callbacks are scheduled on the main run loop
  // - `continuation` is written only from `deviceEvents()` and `cleanup()`,
  //   both called from the main thread
  // - `deviceEvents()` terminates any existing stream before creating a new one

  private let manager: IOHIDManager
  private var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  private let seizeLock = NSLock()
  private var seizedByLocation: [UInt32: [IOHIDDevice]] = [:]
  private let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()

  /// Creates a new stream that matches HID gamepad devices.
  ///
  /// - Parameter virtualProfile: The virtual device profile to exclude from detection.
  public init(
    virtualProfile _: VirtualDeviceProfile = .default,
    additionalProfileIdentifiers: [DeviceIdentifier] = []
  ) {
    manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var matches: [[String: Any]] = [
      [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
      ]
    ]
    matches += additionalProfileIdentifiers.map {
      [kIOHIDVendorIDKey: Int($0.vendorID), kIOHIDProductIDKey: Int($0.productID)]
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
  }

  /// Returns a live stream of HID device events (connect, disconnect, input report).
  ///
  /// Only one stream can be active at a time. The stream ends when its
  /// consuming task is cancelled.
  public func deviceEvents() -> AsyncStream<HIDDeviceEvent> {
    if continuation != nil { cleanup() }
    return AsyncStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in self?.cleanup() }
      self.registerCallbacks()
    }
  }

  // MARK: - Callback registration

  /// Registers IOKit callbacks for device matching, removal, and input reports,
  /// then opens the HID manager on the main run loop.
  private func registerCallbacks() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
    IOHIDManagerRegisterInputReportCallback(manager, Self.inputReportCallback, context)
    IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueCallback, context)
    // CRITICAL: schedule BEFORE open
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  /// Unschedules the HID manager from the run loop, closes it, and finishes
  /// the async stream.
  private func cleanup() {
    IOHIDManagerUnscheduleFromRunLoop(
      manager,
      CFRunLoopGetMain(),
      CFRunLoopMode.defaultMode.rawValue
    )
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    seizeLock.withLock {
      for devices in seizedByLocation.values {
        for device in devices {
          IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
      }
      seizedByLocation.removeAll()
    }
    eventAdapter.reset()
    continuation?.finish()
    continuation = nil
  }

  public func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    setReport(locationID: locationID, report: report, type: kIOHIDReportTypeOutput, label: "Output")
  }

  public func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) -> Bool {
    setReport(
      locationID: locationID,
      report: report,
      type: kIOHIDReportTypeFeature,
      label: "Feature"
    )
  }

  public func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) -> Data?
  {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return nil }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return nil }

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
      if result == kIOReturnSuccess { return Data(bytes.prefix(reportLength)) }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] Feature report read failed for loc=\(locationID)"
        + " report=0x\(String(format: "%02X", request.reportID)) kr=\(lastResult)"
    )
    return nil
  }

  private func setReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport,
    type: IOHIDReportType,
    label: String
  ) -> Bool {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return false }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return false }

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
      if result == kIOReturnSuccess { return true }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] \(label) report failed for loc=\(locationID)"
        + " report=0x\(String(format: "%02X", report.reportID)) kr=\(lastResult)"
    )
    return false
  }

  // MARK: - Event handlers

  /// Reads device properties and yields a `.connected` event into the stream.
  private func handleDeviceAdded(_ device: IOHIDDevice) {
    let vid = deviceProperty(device, kIOHIDVendorIDKey)
    let pid = deviceProperty(device, kIOHIDProductIDKey)
    let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
    let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    let syntheticProperty = IOHIDDeviceGetProperty(device, "kIOHIDGCSyntheticDeviceKey" as CFString)
    let loc = deviceProperty(device, kIOHIDLocationIDKey)
    let locationID = UInt32(truncatingIfNeeded: loc)
    guard
      PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: serial,
        productName: productName,
        transport: transport.isEmpty ? nil : transport,
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    else { return }
    guard
      eventAdapter.add(
        deviceID: trackingID(for: device),
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    else { return }

    // Try to take exclusive access so SDL sees only the virtual controller (no duplicates).
    // This is best-effort; if it fails we still function, but users may see SDL-0/SDL-1 conflicts.
    let seizeKr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    if seizeKr == kIOReturnSuccess {
      seizeLock.withLock {
        var devices = seizedByLocation[locationID] ?? []
        if !devices.contains(where: { CFEqual($0, device) }) {
          devices.append(device)
          seizedByLocation[locationID] = devices
        }
      }
    }

    continuation?.yield(
      .connected(
        vendorID: UInt16(truncatingIfNeeded: vid),
        productID: UInt16(truncatingIfNeeded: pid),
        serialNumber: serial,
        locationID: locationID,
        productName: productName,
        transport: transport.isEmpty ? nil : transport
      )
    )
  }

  /// Yields a `.disconnected` event when IOKit reports a device removal.
  private func handleDeviceRemoved(_ device: IOHIDDevice) {
    let deviceID = trackingID(for: device)
    let removal = eventAdapter.remove(deviceID: deviceID)
    guard removal.wasTracked else { return }
    let vid = deviceProperty(device, kIOHIDVendorIDKey)
    let pid = deviceProperty(device, kIOHIDProductIDKey)
    let loc = deviceProperty(device, kIOHIDLocationIDKey)
    let locationID = UInt32(truncatingIfNeeded: loc)
    seizeLock.withLock {
      guard var devices = seizedByLocation[locationID] else { return }
      let removed = devices.filter { CFEqual($0, device) }
      devices.removeAll { CFEqual($0, device) }
      for removedDevice in removed {
        IOHIDDeviceClose(removedDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
      }
      if devices.isEmpty {
        seizedByLocation.removeValue(forKey: locationID)
        return
      }
      seizedByLocation[locationID] = devices
    }
    if removal.shouldEmitDisconnect {
      continuation?.yield(
        .disconnected(
          vendorID: UInt16(truncatingIfNeeded: vid),
          productID: UInt16(truncatingIfNeeded: pid),
          locationID: locationID
        )
      )
    }
  }

  /// Copies raw report bytes and yields an `.inputReport` event.
  private func handleInputReport(
    deviceID: UInt64,
    locationID: UInt32,
    reportID: UInt8,
    report: UnsafePointer<UInt8>,
    reportLength: CFIndex
  ) {
    guard eventAdapter.acceptsInput(deviceID: deviceID) else { return }
    var bytes = [UInt8](UnsafeBufferPointer(start: report, count: reportLength))
    if reportID != 0, bytes.first != reportID { bytes.insert(reportID, at: 0) }
    continuation?.yield(.inputReport(locationID: locationID, reportID: reportID, data: Data(bytes)))
  }

  /// Yields one descriptor-decoded input element value.
  private func handleInputValue(_ value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let device = IOHIDElementGetDevice(element)
    let loc = deviceProperty(device, kIOHIDLocationIDKey)
    let deviceID = trackingID(for: device)
    guard eventAdapter.acceptsInput(deviceID: deviceID) else { return }
    let semanticValue = HIDElementValue(
      usagePage: IOHIDElementGetUsagePage(element),
      usage: IOHIDElementGetUsage(element),
      logicalMinimum: IOHIDElementGetLogicalMin(element),
      logicalMaximum: IOHIDElementGetLogicalMax(element),
      integerValue: IOHIDValueGetIntegerValue(value)
    )
    continuation?.yield(
      .inputValue(locationID: UInt32(truncatingIfNeeded: loc), value: semanticValue)
    )
  }

  private func trackingID(for device: IOHIDDevice) -> UInt64 {
    UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
  }

  /// Reads an integer property from an IOKit HID device.
  ///
  /// Returns 0 if missing.
  private func deviceProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  // MARK: - C-convention callbacks

  private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceAdded(device)
  }

  private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleDeviceRemoved(device)
  }

  private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
  }

  private static let inputReportCallback: IOHIDReportCallback = {
    context,
    _,
    sender,
    _,
    reportID,
    report,
    length in
    guard let context, let sender else { return }
    let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
    let loc = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
    let stream = Unmanaged<HIDDeviceStream>.fromOpaque(context).takeUnretainedValue()
    stream.handleInputReport(
      deviceID: stream.trackingID(for: device),
      locationID: UInt32(truncatingIfNeeded: loc),
      reportID: UInt8(truncatingIfNeeded: reportID),
      report: report,
      reportLength: length
    )
  }
}
