import Foundation
import IOKit
import IOKit.hid

extension DextOutputDispatcher {
  // MARK: - Connection management

  /// Enables or disables DriverKit output injection.
  ///
  /// When disabled, any open IOHID device handle is closed and future dispatch calls are no-ops.
  public func setEnabled(_ isEnabled: Bool) {
    let shouldClose = connectionLock.withLock { () -> Bool in
      let changed = enabled != isEnabled
      enabled = isEnabled
      return changed && !isEnabled
    }
    if shouldClose { closeDevice() }
  }

  public func isConnected() -> Bool { connectionLock.withLock { hidDevice != nil } }

  /// Best-effort: when enabled, tries to seize the DriverKit virtual HID device so
  /// SDL/IOKit apps prefer the user-space controller (Compatibility mode) and do not
  /// accidentally open the idle DriverKit device.
  ///
  /// This does not uninstall/disable the system extension; it only attempts exclusive open.
  public func setCompatibilitySeizeEnabled(_ enabled: Bool) {
    if enabled {
      let shouldAttempt = seizeLock.withLock { () -> Bool in
        compatibilitySeizeRequested = true
        return seizedDevice == nil
      }
      if shouldAttempt { attemptCompatibilitySeize() }
    } else {
      let (oldDevice, oldMgr) = seizeLock.withLock { () -> (IOHIDDevice?, IOHIDManager?) in
        compatibilitySeizeRequested = false
        seizeRetryScheduled = false
        let d = seizedDevice
        let m = seizedManager
        seizedDevice = nil
        seizedManager = nil
        return (d, m)
      }
      if let device = oldDevice {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
      }
      if let mgr = oldMgr { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
  }

  func attemptCompatibilitySeize() {
    let shouldTry = seizeLock.withLock { compatibilitySeizeRequested && seizedDevice == nil }
    guard shouldTry else { return }

    if let (device, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) {
      seizeLock.withLock {
        seizedDevice = device
        seizedManager = mgr
        seizeRetryScheduled = false
      }
      return
    }

    let shouldSchedule = seizeLock.withLock { () -> Bool in
      guard compatibilitySeizeRequested && seizedDevice == nil && !seizeRetryScheduled else {
        return false
      }
      seizeRetryScheduled = true
      return true
    }
    guard shouldSchedule else { return }

    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.seizeLock.withLock { self.seizeRetryScheduled = false }
      self.attemptCompatibilitySeize()
    }
  }

  @discardableResult public func connect() -> Bool {
    guard connectionLock.withLock({ enabled }) else { return false }
    guard let (device, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeNone)) else {
      print("[DextOutputDispatcher] Virtual gamepad not found -- not installed or not approved")
      return false
    }
    connectionLock.withLock {
      hidDevice = device
      hidManager = mgr
    }
    print(
      "[DextOutputDispatcher] Connected to virtual gamepad "
        + "(VID:\(profile.vendorID) PID:\(profile.productID))"
    )
    return true
  }

  func closeDevice() {
    let (oldDevice, oldMgr) = connectionLock.withLock { () -> (IOHIDDevice?, IOHIDManager?) in
      let d = hidDevice
      let m = hidManager
      hidDevice = nil
      hidManager = nil
      return (d, m)
    }
    if let device = oldDevice { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    if let mgr = oldMgr { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }
  }

  func findDevice(openOptions: IOOptionBits) -> (IOHIDDevice, IOHIDManager)? {
    recordConnectionAttempt()
    // Do NOT match by VID/PID.
    //
    // During development and during sysext replacement/upgrade, the installed dext may be an
    // older build with a different VID/PID than the Swift layer expects. Also, our virtual
    // identity is intentionally not tied to any real controller's VID/PID.
    //
    // Instead, broadly enumerate HID devices and identify the dext via IOUserClass / serial.
    func openManager(_ matching: CFDictionary?) -> IOHIDManager {
      let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
      IOHIDManagerSetDeviceMatching(mgr, matching)
      let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      if openResult != kIOReturnSuccess {
        print("[DextOutputDispatcher] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
      }
      return mgr
    }

    func copyDevices(_ mgr: IOHIDManager) -> [IOHIDDevice] {
      guard let rawDevices = IOHIDManagerCopyDevices(mgr) else { return [] }
      let count = CFSetGetCount(rawDevices)
      guard count > 0 else { return [] }
      var values = [UnsafeRawPointer?](repeating: nil, count: count)
      CFSetGetValues(rawDevices, &values)
      return values.compactMap { raw in
        guard let raw else { return nil }
        return unsafeBitCast(raw, to: IOHIDDevice.self)
      }
    }

    func copyServiceDevices() -> [IOHIDDevice] {
      var iterator: io_iterator_t = 0
      let kr = IOServiceGetMatchingServices(
        kIOMasterPortDefault,
        IOServiceMatching("AppleUserHIDDevice"),
        &iterator
      )
      guard kr == KERN_SUCCESS else { return [] }
      defer { IOObjectRelease(iterator) }

      var result: [IOHIDDevice] = []
      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }
        if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { result.append(device) }
      }
      return result
    }

    func registryString(_ service: io_object_t, _ key: String) -> String? {
      let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
      return value as? String
    }

    func registryInt(_ service: io_object_t, _ key: String) -> Int {
      let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
      return value as? Int ?? 0
    }

    func findServiceDevice(openOptions: IOOptionBits) -> (IOHIDDevice, IOReturn)? {
      var iterator: io_iterator_t = 0
      let kr = IOServiceGetMatchingServices(
        kIOMasterPortDefault,
        IOServiceMatching("AppleUserHIDDevice"),
        &iterator
      )
      guard kr == KERN_SUCCESS else { return nil }
      defer { IOObjectRelease(iterator) }

      while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        defer { IOObjectRelease(service) }

        let serial = registryString(service, kIOHIDSerialNumberKey as String)
        if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { continue }

        let ioUserClass = registryString(service, "IOUserClass")
        let vendorID = registryInt(service, kIOHIDVendorIDKey as String)
        let productID = registryInt(service, kIOHIDProductIDKey as String)
        let productName = registryString(service, kIOHIDProductKey as String)
        let manufacturer = registryString(service, kIOHIDManufacturerKey as String)
        let location = registryInt(service, kIOHIDLocationIDKey as String)

        var score = 0
        if ioUserClass == "OpenJoystickVirtualHIDDevice" { score += 1_000_000 }
        if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { score += 100_000 }
        if location == Int(VirtualDeviceIdentityConstants.driverKitLocationID) { score += 10_000 }
        if vendorID == profile.vendorID && productID == profile.productID { score += 50_000 }
        if productName == profile.productName { score += 5_000 }
        if manufacturer == profile.manufacturer { score += 1_000 }
        guard score > 0, let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
          continue
        }

        let ret = IOHIDDeviceOpen(device, openOptions)
        recordDiscoverySummary(
          "service-open \(productName ?? "?")|\(serial ?? "?")|\(ioUserClass ?? "?")|"
            + "\(vendorID):\(productID)|score=\(score) "
            + "ret=\(String(format: "0x%08x", UInt32(bitPattern: ret)))"
        )
        return (device, ret)
      }
      return nil
    }

    // Broad match first. On recent macOS/Swift toolchains the usage-filtered
    // IOHIDManager query can omit the DriverKit HID service even though a broad
    // query exposes it with the expected serial, VID/PID, product, and IOUserClass.
    let mgr = openManager(nil)
    let managerDevices = copyDevices(mgr)
    let devices = managerDevices.isEmpty ? copyServiceDevices() : managerDevices

    guard !devices.isEmpty else {
      IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
      recordConnectionResult(kIOReturnNotFound)
      return nil
    }

    func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
      IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
      IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
    }

    func score(_ device: IOHIDDevice) -> Int {
      // Prefer the DriverKit virtual device and avoid matching the user-space IOHIDUserDevice
      // (they share VID/PID for compatibility).
      let ioUserClass = strProp(device, "IOUserClass")
      let serial = strProp(device, kIOHIDSerialNumberKey as String)
      let location = intProp(device, kIOHIDLocationIDKey as String)
      let vendorID = intProp(device, kIOHIDVendorIDKey as String)
      let productID = intProp(device, kIOHIDProductIDKey as String)
      let productName = strProp(device, kIOHIDProductKey as String)
      let manufacturer = strProp(device, kIOHIDManufacturerKey as String)

      if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { return Int.min / 2 }
      if ioUserClass == "IOHIDUserDevice" { return Int.min / 2 }
      // Extra guard: our user-space devices live in the OJ namespace.
      let rawLocation = UInt32(truncatingIfNeeded: location)
      let isUserSpaceLocation =
        (rawLocation & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace
      if rawLocation != VirtualDeviceIdentityConstants.driverKitLocationID && isUserSpaceLocation {
        return Int.min / 2
      }

      var s = 0
      if ioUserClass == "OpenJoystickVirtualHIDDevice" { s += 1_000_000 }
      if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { s += 100_000 }
      if location == Int(VirtualDeviceIdentityConstants.driverKitLocationID) { s += 10_000 }
      if vendorID == profile.vendorID && productID == profile.productID { s += 50_000 }
      if productName == profile.productName { s += 5_000 }
      if manufacturer == profile.manufacturer { s += 1_000 }

      // If we don't have any strong indicator that this is our dext device,
      // do not treat it as a candidate. Otherwise we risk opening a real controller
      // and blasting it with output reports.
      if s == 0 { return Int.min / 2 }

      if (strProp(device, kIOHIDTransportKey as String) ?? "") == "USB" { s += 100 }
      return s
    }

    let candidates = devices.map { ($0, score($0)) }.sorted { a, b in a.1 > b.1 }

    let summary = candidates.prefix(6).map { device, score in
      let product = strProp(device, kIOHIDProductKey as String) ?? "?"
      let serial = strProp(device, kIOHIDSerialNumberKey as String) ?? "?"
      let ioUserClass = strProp(device, "IOUserClass") ?? "?"
      let vendorID = intProp(device, kIOHIDVendorIDKey as String)
      let productID = intProp(device, kIOHIDProductIDKey as String)
      return "\(product)|\(serial)|\(ioUserClass)|\(vendorID):\(productID)|score=\(score)"
    }.joined(separator: "; ")
    recordDiscoverySummary(
      "devices=\(devices.count), candidates=\(candidates.count), top=[\(summary)]"
    )

    var lastOpenResult: IOReturn = kIOReturnNotFound
    for (device, s) in candidates {
      if s <= Int.min / 4 { continue }  // filtered (likely our user-space device)
      let ret = IOHIDDeviceOpen(device, openOptions)
      recordDiscoverySummary(
        "open \(strProp(device, kIOHIDProductKey as String) ?? "?") score=\(s) "
          + "ret=\(String(format: "0x%08x", UInt32(bitPattern: ret)))"
      )
      lastOpenResult = ret
      if ret == kIOReturnSuccess {
        recordConnectionResult(kIOReturnSuccess)
        return (device, mgr)
      }
    }

    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    recordConnectionResult(lastOpenResult)
    return nil
  }
}
