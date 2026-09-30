import Foundation
import IOKit
import IOKit.hid

extension HIDDeviceStream {
  /// Admits a physical device, opens it, and yields a `.connected` event into the stream. A device
  /// the running macOS exposes as a native gamepad is opened shared for input but never seized.
  ///
  /// Returns the stream-level access failure instead of admitting the device when
  /// `failingOnAccessDenial` is set and the shared open is denied.
  @discardableResult
  func handleDeviceAdded(
    _ device: IOHIDDevice,
    failingOnAccessDenial: Bool = false
  ) -> HIDDeviceEvent? {
    dispatchPrecondition(condition: .onQueue(.main))
    guard !AppleGameControllerSyntheticHID.isSynthetic(device: device) else { return nil }
    let deviceID = trackingID(for: device)
    guard
      let identity = PhysicalHIDIdentity(
        vendorID: unsignedProperty(device, kIOHIDVendorIDKey),
        productID: unsignedProperty(device, kIOHIDProductIDKey)
      )
    else {
      print("[HIDDeviceStream] Skipping device with missing or unrepresentable VID/PID")
      return nil
    }
    let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
    let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    let syntheticProperty = IOHIDDeviceGetProperty(
      device,
      AppleGameControllerSyntheticHID.propertyKey as CFString
    )
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
    else { return nil }
    // macOS already serves a native gamepad, so OJD only observes its input and never seizes it.
    let nativePassThrough = Self.isNativeGamepad(device)
    guard
      eventAdapter.add(
        deviceID: deviceID,
        locationID: locationID,
        syntheticProperty: syntheticProperty,
        serviceID: registryEntryID(for: device),
        nativePassThrough: nativePassThrough,
        disconnectsIndividually: roleModels.contains(identity)
      )
    else { return nil }
    // The shared open keeps input flowing while the seize is released for another client.
    let openKr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if failingOnAccessDenial, let failure = Self.accessFailure(forInitialOpenResult: openKr) {
      _ = eventAdapter.remove(deviceID: deviceID)
      return failure
    }
    // macOS keeps every interface of a native controller, so a sibling is never seized either.
    if !nativePassThrough, !eventAdapter.hasNativeDevice(locationID: locationID) {
      seizeInput(device, deviceID: deviceID, locationID: locationID)
    }
    let physicalDevice = physicalDeviceObservation(
      for: device,
      vendorID: identity.vendorID,
      productID: identity.productID,
      transportProperty: transport.isEmpty ? nil : transport,
      nativePassThrough: nativePassThrough
    )
    let connection = HIDDeviceConnection(
      physicalDevice: physicalDevice,
      routingLocationID: locationID
    )
    seizeLock.withLock { connectionsByDeviceID[deviceID] = connection }

    let ownership =
      nativePassThrough ? HIDInputOwnership.unknown : eventAdapter.ownership(locationID: locationID)
    continuation?.yield(.connected(connection: connection, ownership: ownership))
    // Attach input only after `.connected` is queued so no report precedes its connection.
    if openKr == kIOReturnSuccess { attachInput(device, deviceID: deviceID) }
    return nil
  }

  /// Seizes a shared-open device and records whether isolation was acquired; a failed seize keeps
  /// shared input for existing profiles.
  func seizeInput(_ device: IOHIDDevice, deviceID: UInt64, locationID: UInt32) {
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
    let ownership: HIDInputOwnership
    switch seizeKr {
    case kIOReturnSuccess: ownership = .exclusive
    case kIOReturnExclusiveAccess: ownership = .ownedByAnotherClient
    case kIOReturnNotPermitted, kIOReturnNotPrivileged: ownership = .accessDenied
    default: ownership = .acquisitionFailed
    }
    eventAdapter.updateOwnership(ownership, deviceID: deviceID)
  }

  /// Routes input reports of one opened device into this stream. Element values are routed only
  /// after a bound driver asks for them, since IOKit decodes every element of every report.
  private func attachInput(_ device: IOHIDDevice, deviceID: UInt64) {
    let size = max(Int(unsignedProperty(device, kIOHIDMaxInputReportSizeKey) ?? 0), 1)
    let reportBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: size)
    reportBuffer.initialize(repeating: 0)
    let context = Unmanaged.passUnretained(self).toOpaque()
    if let baseAddress = reportBuffer.baseAddress {
      IOHIDDeviceRegisterInputReportCallback(
        device,
        baseAddress,
        size,
        Self.inputReportCallback,
        context
      )
    }
    seizeLock.withLock {
      sharedOpenByDeviceID[deviceID] = SharedOpenDevice(device: device, reportBuffer: reportBuffer)
    }
  }

  /// Starts routing descriptor-decoded element values of a connection's shared open, for a
  /// driver that parses element values instead of raw reports.
  @MainActor
  func routeElementValues(connection: HIDDeviceConnection) {
    let device = seizeLock.withLock { () -> IOHIDDevice? in
      guard let deviceID = connectionsByDeviceID.first(where: { $0.value == connection })?.key
      else { return nil }
      return sharedOpenByDeviceID[deviceID]?.device
    }
    guard let device else { return }
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, context)
  }

  /// Never-freed report buffer a closed device is pointed at before its own buffer is freed.
  /// IOKit keeps the buffer of the last registration with a non-nil callback: a nil-callback
  /// registration does not replace it, so a later delivery on the device object would write into
  /// the freed buffer. Input callbacks run only on main, so only main writes this buffer, and IOKit
  /// copies at most its one-byte length.
  nonisolated(unsafe) private static let detachedReportBuffer = UnsafeMutablePointer<UInt8>
    .allocate(capacity: 1)
  private static let detachedReportCallback: IOHIDReportCallback = { _, _, _, _, _, _, _ in }

  /// Unregisters a shared open's callbacks, closes it, and frees its report buffer. Runs on main,
  /// where input callbacks are delivered, so no callback is using the buffer.
  func closeSharedOpen(_ sharedOpen: SharedOpenDevice) {
    let device = sharedOpen.device
    let reportBuffer = sharedOpen.reportBuffer
    // A later delivery on the same device object must not write into the freed buffer.
    IOHIDDeviceRegisterInputReportCallback(
      device,
      Self.detachedReportBuffer,
      1,
      Self.detachedReportCallback,
      nil
    )
    IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    reportBuffer.deallocate()
  }

  private func registryEntryID(for device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    var entryID: UInt64 = 0
    guard service != 0, IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
      return nil
    }
    return entryID
  }

  /// Yields a `.disconnected` event when IOKit reports a device removal.
  func handleDeviceRemoved(_ device: IOHIDDevice) {
    let deviceID = trackingID(for: device)
    let (connection, sharedOpen) = seizeLock.withLock {
      let connection = connectionsByDeviceID.removeValue(forKey: deviceID)
      let sharedOpen = sharedOpenByDeviceID.removeValue(forKey: deviceID)
      for locationID in Array(releasedByLocation.keys) {
        releasedByLocation[locationID]?.removeAll { CFEqual($0, device) }
        if releasedByLocation[locationID]?.isEmpty == true {
          releasedByLocation.removeValue(forKey: locationID)
        }
      }
      for locationID in Array(seizedByLocation.keys) {
        guard var devices = seizedByLocation[locationID] else { continue }
        let removed = devices.filter { CFEqual($0, device) }
        devices.removeAll { CFEqual($0, device) }
        for removedDevice in removed {
          IOHIDDeviceClose(removedDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        if devices.isEmpty {
          seizedByLocation.removeValue(forKey: locationID)
        } else {
          seizedByLocation[locationID] = devices
        }
      }
      return (connection, sharedOpen)
    }
    if let sharedOpen { closeSharedOpen(sharedOpen) }
    let removal = eventAdapter.remove(deviceID: deviceID)
    guard removal.wasTracked else { return }
    guard let connection else {
      print("[HIDDeviceStream] Removed tracked device without its connection snapshot")
      return
    }
    if removal.shouldEmitDisconnect { continuation?.yield(.disconnected(connection: connection)) }
    // The location's remaining devices, if any, now combine to a different ownership.
    if !removal.locationRemoved {
      continuation?.yield(
        .ownershipChanged(
          locationID: connection.routingLocationID,
          ownership: eventAdapter.ownership(locationID: connection.routingLocationID)
        )
      )
    }
  }

  /// Copies raw report bytes and yields an `.inputReport` event.
  func handleInputReport(
    deviceID: UInt64,
    locationID: UInt32,
    reportID: UInt8,
    report: UnsafePointer<UInt8>,
    reportLength: CFIndex
  ) {
    guard eventAdapter.acceptsInput(deviceID: deviceID),
      let connectionID = seizeLock.withLock({ connectionsByDeviceID[deviceID]?.connectionID })
    else { return }
    let bytes = Self.framedInputReport(
      reportID: reportID,
      bytes: [UInt8](UnsafeBufferPointer(start: report, count: reportLength))
    )
    continuation?.yield(
      .inputReport(
        locationID: locationID,
        connectionID: connectionID,
        reportID: reportID,
        data: Data(bytes)
      )
    )
  }

  /// Parsers expect numbered reports to start with their report ID; IOKit may deliver the payload
  /// without it.
  static func framedInputReport(reportID: UInt8, bytes: [UInt8]) -> [UInt8] {
    guard reportID != 0, bytes.first != reportID else { return bytes }
    return [reportID] + bytes
  }

  /// Yields one descriptor-decoded input element value.
  func handleInputValue(_ value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let deviceID = trackingID(for: IOHIDElementGetDevice(element))
    guard eventAdapter.acceptsInput(deviceID: deviceID),
      let connection = seizeLock.withLock({ connectionsByDeviceID[deviceID] })
    else { return }
    let semanticValue = HIDElementValue(
      usagePage: IOHIDElementGetUsagePage(element),
      usage: IOHIDElementGetUsage(element),
      logicalMinimum: IOHIDElementGetLogicalMin(element),
      logicalMaximum: IOHIDElementGetLogicalMax(element),
      integerValue: IOHIDValueGetIntegerValue(value),
      reportID: IOHIDElementGetReportID(element)
    )
    continuation?.yield(
      .inputValue(
        locationID: connection.routingLocationID,
        connectionID: connection.connectionID,
        value: semanticValue
      )
    )
  }

  func trackingID(for device: IOHIDDevice) -> UInt64 {
    UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
  }
}
