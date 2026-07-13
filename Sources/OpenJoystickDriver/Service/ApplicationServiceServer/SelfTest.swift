import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  private final class SelfTestCounter {
    let lock = NSLock()
    private(set) var driverKitValueEvents: Int = 0
    private(set) var driverKitReportEvents: Int = 0
    private(set) var userSpaceValueEvents: Int = 0
    private(set) var userSpaceReportEvents: Int = 0

    enum EventKind {
      case value
      case report
    }

    func record(device: IOHIDDevice, kind: EventKind) {
      // IMPORTANT:
      // IOHIDDevice properties can be incomplete during system-extension replacement/upgrade.
      // Prefer IORegistry properties via IOHIDDeviceGetService for reliable identification.
      func strProp(_ key: String) -> String? {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? String
      }
      func intProp(_ key: String) -> Int {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
          return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int ?? 0
        }
        return IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
      }

      let ioUserClass = strProp("IOUserClass")
      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let location = intProp(kIOHIDLocationIDKey as String)
      let vid = intProp(kIOHIDVendorIDKey as String)
      let pid = intProp(kIOHIDProductIDKey as String)
      let product = strProp(kIOHIDProductKey as String)
      let manufacturer = strProp(kIOHIDManufacturerKey as String)

      let isUserSpace =
        UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || (
          (UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
            == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace
        )
        || (ioUserClass == "IOHIDUserDevice")

      let looksLikeOJDVirtual =
        (vid == VirtualDeviceProfile.default.vendorID)
        && (pid == VirtualDeviceProfile.default.productID)
        && (product == VirtualDeviceProfile.default.productName)
        && (manufacturer == VirtualDeviceProfile.default.manufacturer)

      let isDriverKit =
        (serial == VirtualDeviceIdentityConstants.driverKitSerialNumber)
        || (location == Int(VirtualDeviceIdentityConstants.driverKitLocationID))
        || (ioUserClass == "OpenJoystickVirtualHIDDevice")
        || (!isUserSpace && looksLikeOJDVirtual)

      lock.withLock {
        if isDriverKit {
          switch kind {
          case .value: driverKitValueEvents += 1
          case .report: driverKitReportEvents += 1
          }
        }
        if isUserSpace {
          switch kind {
          case .value: userSpaceValueEvents += 1
          case .report: userSpaceReportEvents += 1
          }
        }
      }
    }
  }

  func runVirtualDeviceSelfTestInternal(
    seconds: Int
  ) async -> ApplicationServiceVirtualDeviceSelfTestPayload {
    let driverKitStartCount = Self.readDriverKitInputReportCount()
    let startStats = dextDispatcher.outputStatsSnapshot()

    let counter = SelfTestCounter()
    let counterPtr = Unmanaged.passRetained(counter).toOpaque()

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // IMPORTANT: do not match only "GamePad" usage here.
    //
    // Some installed dext builds (especially during replacement/upgrade or when the app and dext
    // are temporarily out of sync) may not expose the expected usage keys at the IOHIDManager
    // matching layer. Broad matching keeps the self-test reliable; we filter down to OJD devices
    // in the callback using IOUserClass / serial.
    IOHIDManagerSetDeviceMatching(mgr, nil)

    let callback: IOHIDValueCallback = { context, _, sender, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .value)
      }
    }
    IOHIDManagerRegisterInputValueCallback(mgr, callback, counterPtr)

    let reportCallback: IOHIDReportCallback = { context, _, sender, _, _, _, _ in
      guard let context else { return }
      let counter = Unmanaged<SelfTestCounter>.fromOpaque(context).takeUnretainedValue()
      if let sender {
        let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        counter.record(device: dev, kind: .report)
      }
    }
    IOHIDManagerRegisterInputReportCallback(mgr, reportCallback, counterPtr)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      let code = String(openResult, radix: 16)
      print("[ApplicationServiceServer] Self-test IOHIDManagerOpen warning: \(code)")
    }

    let connectedIdentifiers = await deviceManager.connectedDeviceIdentifiers()
    let syntheticIdentifier =
      connectedIdentifiers.first
      ?? DeviceIdentifier(
        vendorID: 0x4F4A,
        productID: 0x5445,
        serialNumber: "OpenJoystickDriver-SelfTest"
      )
    Task {
      let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
      try? await Task.sleep(nanoseconds: 250_000_000)
      dextDispatcher.sendDiagnosticProbe()
      await userSpace?.dispatch(events: [.buttonPressed(.a)], from: syntheticIdentifier)
      try? await Task.sleep(nanoseconds: 250_000_000)
      await userSpace?.dispatch(events: [.buttonReleased(.a)], from: syntheticIdentifier)
      try? await Task.sleep(nanoseconds: 250_000_000)
      await userSpace?.dispatch(
        events: [.leftStickChanged(x: 0.75, y: 0)],
        from: syntheticIdentifier
      )
      try? await Task.sleep(nanoseconds: 250_000_000)
      await userSpace?.dispatch(events: [.leftStickChanged(x: 0, y: 0)], from: syntheticIdentifier)
    }

    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

    let driverKitEndCount = Self.readDriverKitInputReportCount()
    let endStats = dextDispatcher.outputStatsSnapshot()
    let driverKitDelta: Int? = {
      guard let a = driverKitStartCount, let b = driverKitEndCount else { return nil }
      return max(0, b - a)
    }()
    let setReportSuccessDelta = max(0, endStats.successes - startStats.successes)
    let setReportAttemptDelta = max(0, endStats.attempts - startStats.attempts)
    let setReportFailureDelta = max(0, endStats.failures - startStats.failures)
    let connectionAttemptDelta =
      max(0, endStats.connectionAttempts - startStats.connectionAttempts)
    let connectionSuccessDelta =
      max(0, endStats.connectionSuccesses - startStats.connectionSuccesses)
    let connectionFailureDelta = max(0, endStats.connectionFailures - startStats.connectionFailures)

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: seconds,
      driverKitValueEvents: retained.driverKitValueEvents,
      driverKitReportEvents: retained.driverKitReportEvents,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      userSpaceRequired: virtualDeviceMode == .compatUserSpace || virtualDeviceMode == .both,
      userSpaceStatus: currentUserSpaceStatus(),
      driverKitInputReportDelta: driverKitDelta,
      driverKitSetReportSuccessDelta: setReportSuccessDelta,
      driverKitSetReportAttemptDelta: setReportAttemptDelta,
      driverKitSetReportFailureDelta: setReportFailureDelta,
      driverKitSetReportLastErrorHex: endStats.lastErrorHex,
      driverKitConnectionAttemptDelta: connectionAttemptDelta,
      driverKitConnectionSuccessDelta: connectionSuccessDelta,
      driverKitConnectionFailureDelta: connectionFailureDelta,
      driverKitLastConnectionErrorHex: endStats.lastConnectionErrorHex,
      driverKitDiscoverySummary: endStats.lastDiscoverySummary
    )
  }

  /// Best-effort read of the DriverKit virtual device DebugState InputReportCount from IORegistry.
  ///
  /// This avoids relying on IOHID input callbacks (which can be flaky during sysext replacement).
  private static func readDriverKitInputReportCount() -> Int? {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("AppleUserHIDDevice")
    let kr = IOServiceGetMatchingServices(mach_port_t(MACH_PORT_NULL), matching, &iterator)
    if kr != KERN_SUCCESS { return nil }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }

      func strProp(_ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? String
      }

      func intProp(_ key: String) -> Int {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? Int ?? 0
      }

      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let ioUserClass = strProp("IOUserClass")
      let product = strProp(kIOHIDProductKey as String)
      let manufacturer = strProp(kIOHIDManufacturerKey as String)
      let vid = intProp(kIOHIDVendorIDKey as String)
      let pid = intProp(kIOHIDProductIDKey as String)

      let looksLikeOJDVirtual =
        (vid == VirtualDeviceProfile.default.vendorID)
        && (pid == VirtualDeviceProfile.default.productID)
        && (product == VirtualDeviceProfile.default.productName)
        && (manufacturer == VirtualDeviceProfile.default.manufacturer)

      let isDriverKit =
        (serial == VirtualDeviceIdentityConstants.driverKitSerialNumber)
        || (ioUserClass == "OpenJoystickVirtualHIDDevice")
        || looksLikeOJDVirtual

      if !isDriverKit { continue }

      guard
        let debug = IORegistryEntryCreateCFProperty(
          service,
          "DebugState" as CFString,
          kCFAllocatorDefault,
          0
        )?.takeRetainedValue() as? [String: Any]
      else { return nil }

      if let i = debug["InputReportCount"] as? Int { return i }
      if let d = debug["InputReportCount"] as? Double { return Int(d) }
      return nil
    }

    return nil
  }
}
