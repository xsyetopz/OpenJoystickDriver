import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

extension HIDDeviceStream {
  /// Admits a physical device, opens it, and yields a `.connected` event into the stream.
  ///
  /// A device the running macOS exposes as a native gamepad is opened shared for input but never
  /// seized.
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
      let model = ControllerModelID(
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
    let nativePassThrough = Self.nativePassThrough(
      device,
      vendorID: model.vendorID,
      productID: model.productID
    )
    guard
      eventAdapter.add(
        deviceID: deviceID,
        locationID: locationID,
        syntheticProperty: syntheticProperty,
        serviceID: registryEntryID(for: device),
        nativePassThrough: nativePassThrough,
        disconnectsIndividually: roleModels.contains(model)
      )
    else { return nil }
    // macOS keeps every interface of a native controller, so a sibling is never seized either.
    let wantsSeize = !nativePassThrough && !eventAdapter.hasNativeDevice(locationID: locationID)
    let claim = HIDInputClaim.admit(port: HIDDeviceOpenPort(device: device), seize: wantsSeize)
    let openKr = claim.inputResult
    if failingOnAccessDenial, let failure = Self.accessFailure(forInitialOpenResult: openKr) {
      _ = eventAdapter.remove(deviceID: deviceID)
      return failure
    }
    if wantsSeize { record(claim, device: device, deviceID: deviceID, locationID: locationID) }
    let physicalDevice = physicalDeviceObservation(
      for: device,
      vendorID: model.vendorID,
      productID: model.productID,
      transportProperty: transport.isEmpty ? nil : transport,
      nativePassThrough: nativePassThrough,
      systemListsGameController: GCController.supportsHIDDevice(device)
    )
    let connection = HIDDeviceConnection(
      physicalDevice: physicalDevice,
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
    seizeLock.withLock { connectionsByDeviceID[deviceID] = connection }

    let ownership =
      nativePassThrough ? HIDInputOwnership.unknown : eventAdapter.ownership(locationID: locationID)
    continuation?.yield(.connected(connection: connection, ownership: ownership))
    // Attach input only after `.connected` is queued so no report precedes its connection.
    if openKr == kIOReturnSuccess { attachInput(device, deviceID: deviceID) }
    return nil
  }

  /// macOS already serves a native gamepad, so OJD only observes its input and never seizes it,
  /// unless the controller's record takes ownership for OJD.
  static func nativePassThrough(_ device: IOHIDDevice, vendorID: UInt16, productID: UInt16) -> Bool
  {
    GCController.supportsHIDDevice(device)
      && !DeviceCatalog.current.withLock {
        $0.takesOwnership(of: ControllerModelID(vendorID: vendorID, productID: productID))
      }
  }

  /// Admits again each tracked device of a model in `models` whose native pass-through differs
  /// from the current records, so a changed `ownership` seizes or releases it without a replug.
  ///
  /// Every tracked interface at an affected location is removed before any is added, so no sibling
  /// keeps the native flag it had. Returns the connections it admitted.
  @MainActor
  func reevaluateOwnership(of models: Set<ControllerModelID>) -> Set<UUID> {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
      return []
    }
    let devicesByID = Dictionary(devices.map { (trackingID(for: $0), $0) }) { first, _ in first }
    let tracked = seizeLock.withLock { connectionsByDeviceID }
    let cycled = Self.ownershipReevaluation(
      tracked: tracked.filter { devicesByID[$0.key] != nil },
      models: models
    ) { deviceID, connection in
      guard let device = devicesByID[deviceID], let vendorID = connection.physicalDevice.vendorID,
        let productID = connection.physicalDevice.productID
      else { return connection.physicalDevice.nativePassThrough }
      return Self.nativePassThrough(device, vendorID: vendorID, productID: productID)
    }
    let cycledDevices = cycled.sorted().compactMap { devicesByID[$0] }
    for device in cycledDevices { handleDeviceRemoved(device) }
    for device in cycledDevices { handleDeviceAdded(device) }
    return seizeLock.withLock {
      Set(cycled.compactMap { connectionsByDeviceID[$0]?.connectionID })
    }
  }

  /// The tracked device IDs to admit again: every device at a location where a device of a model
  /// in `models` has a recomputed native pass-through that differs from its connection's.
  static func ownershipReevaluation(
    tracked: [UInt64: HIDDeviceConnection],
    models: Set<ControllerModelID>,
    nativePassThrough: (UInt64, HIDDeviceConnection) -> Bool
  ) -> Set<UInt64> {
    let changedLocations = Set(
      tracked.compactMap { deviceID, connection -> UInt32? in
        guard let model = connection.physicalDevice.model, models.contains(model),
          nativePassThrough(deviceID, connection) != connection.physicalDevice.nativePassThrough
        else { return nil }
        return connection.ioKitLocationID
      }
    )
    return Set(tracked.filter { changedLocations.contains($0.value.ioKitLocationID) }.keys)
  }

  /// Records the outcome of a seize request: the device joins the location's seized devices when
  /// the seize holds, and its ownership names the result, so a refused seize is never reported as
  /// exclusive.
  func record(
    _ claim: HIDInputClaim,
    device: IOHIDDevice,
    deviceID: UInt64,
    locationID: UInt32
  ) {
    if claim.seized {
      seizeLock.withLock {
        var devices = seizedByLocation[locationID] ?? []
        if !devices.contains(where: { CFEqual($0, device) }) {
          devices.append(device)
          seizedByLocation[locationID] = devices
        }
      }
    }
    if let ownership = claim.ownership {
      eventAdapter.updateOwnership(ownership, deviceID: deviceID)
    }
  }

  /// Routes input reports of one opened device into this stream.
  ///
  /// Element values are routed only after a bound driver asks for them, since IOKit decodes every
  /// element of every report.
  func attachInput(_ device: IOHIDDevice, deviceID: UInt64) {
    let size = max(Int(unsignedProperty(device, kIOHIDMaxInputReportSizeKey) ?? 0), 1)
    sizeReportQueue(device)
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

  /// Sizes the kernel report queue of an open device so a reader that is late by a second or more
  /// loses no report.
  ///
  /// A refused size leaves the default queue and is written to the log; the drop count of `ojd
  /// diagnose` shows what the default queue loses.
  func sizeReportQueue(_ device: IOHIDDevice) {
    let reportSize = Int(unsignedProperty(device, kIOHIDMaxInputReportSizeKey) ?? 0)
    guard !HIDInputReportQueue.size(device, maxInputReportSize: reportSize) else { return }
    print("[HIDDeviceStream] Report queue not sized for a device with \(reportSize)-byte reports")
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
  ///
  /// IOKit keeps the buffer of the last registration with a non-nil callback: a nil-callback
  /// registration does not replace it, so a later delivery on the device object would write into
  /// the freed buffer. Input callbacks run only on main, so only main writes this buffer, and IOKit
  /// copies at most its one-byte length.
  nonisolated(unsafe) private static let detachedReportBuffer = UnsafeMutablePointer<UInt8>
    .allocate(capacity: 1)
  /// A report callback that does nothing, set in place of the input callback when a device
  /// detaches.
  private static let detachedReportCallback: IOHIDReportCallback = { _, _, _, _, _, _, _ in }

  /// Unregisters a shared open's callbacks, closes it, and frees its report buffer.
  ///
  /// Runs on main, where input callbacks are delivered, so no callback is using the buffer.
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

  /// Returns the IORegistry entry ID of `device`, or nil when it has no service.
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
          address: connection.routingAddress,
          ownership: eventAdapter.ownership(locationID: connection.ioKitLocationID)
        )
      )
    }
  }

  /// Copies raw report bytes and yields an `.inputReport` event.
  func handleInputReport(
    deviceID: UInt64,
    reportID: UInt8,
    report: UnsafePointer<UInt8>,
    reportLength: CFIndex
  ) {
    guard eventAdapter.acceptsInput(deviceID: deviceID),
      let connection = seizeLock.withLock({ connectionsByDeviceID[deviceID] })
    else { return }
    let bytes = Self.framedInputReport(
      reportID: reportID,
      bytes: [UInt8](UnsafeBufferPointer(start: report, count: reportLength))
    )
    continuation?.yield(
      .inputReport(
        address: connection.routingAddress,
        connectionID: connection.connectionID,
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
        address: connection.routingAddress,
        connectionID: connection.connectionID,
        value: semanticValue
      )
    )
  }

  /// Returns the ID that identifies `device` while the stream tracks it.
  func trackingID(for device: IOHIDDevice) -> UInt64 {
    UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
  }
}

extension HIDDeviceConnection {
  /// The IOKit location of a connection ``HIDDeviceStream`` admitted; each one has an IOKit
  /// routing address.
  var ioKitLocationID: UInt32 { routingAddress.locationID ?? 0 }
}
