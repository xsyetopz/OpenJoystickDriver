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
      let version = intProp(kIOHIDVersionNumberKey as String)
      let transport = strProp(kIOHIDTransportKey as String)
      let manufacturer = strProp(kIOHIDManufacturerKey as String)
      let product = strProp(kIOHIDProductKey as String)
      let primaryUsagePage = intProp(kIOHIDPrimaryUsagePageKey as String)
      let primaryUsage = intProp(kIOHIDPrimaryUsageKey as String)

      let isUserSpace =
        UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
          == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)

      let isDriverKit = DriverKitRelayIdentity.matches(
        runtimeClass: ioUserClass,
        transport: transport,
        vendorID: UInt32(truncatingIfNeeded: vid),
        productID: UInt32(truncatingIfNeeded: pid),
        versionNumber: UInt32(truncatingIfNeeded: version),
        locationID: UInt32(truncatingIfNeeded: location),
        manufacturer: manufacturer,
        product: product,
        serialNumber: serial,
        primaryUsagePage: UInt32(truncatingIfNeeded: primaryUsagePage),
        primaryUsage: UInt32(truncatingIfNeeded: primaryUsage)
      )

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

  func runVirtualDeviceSelfTestInternal(seconds: Int) async
    -> ApplicationServiceVirtualDeviceSelfTestPayload
  {
    let driverKitStartRuntimeStats = await driverKitDispatcher.runtimeStatisticsSnapshot()
    let startStats = await driverKitDispatcher.outputStatsSnapshot()

    let counter = SelfTestCounter()
    let counterPtr = Unmanaged.passRetained(counter).toOpaque()

    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    // IMPORTANT: do not match only "GamePad" usage here.
    //
    // Some installed extension builds (especially during replacement/upgrade or when the app and runtime
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
    let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
    let driverKitRequired = DriverKitRelayRequirement.currentExecutableRequiresRelay()
    async let driverKitProbe: Int = runDriverKitProbe(seconds: seconds)
    async let userSpaceExercise: Void = exerciseUserSpaceSelfTest(
      userSpace,
      identifier: syntheticIdentifier
    )
    async let observationWindow: Void = waitForSelfTestWindow(seconds: seconds)
    _ = await (driverKitProbe, userSpaceExercise, observationWindow)

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

    let driverKitEndRuntimeStats = await driverKitDispatcher.runtimeStatisticsSnapshot()
    let endStats = await driverKitDispatcher.outputStatsSnapshot()
    let driverKitDelta: Int? = {
      guard let start = driverKitStartRuntimeStats, let end = driverKitEndRuntimeStats else {
        return nil
      }
      let delta =
        end.inputReportSuccesses >= start.inputReportSuccesses
        ? end.inputReportSuccesses - start.inputReportSuccesses : 0
      return Int(clamping: delta)
    }()
    let submissionSuccessDelta = max(0, endStats.successes - startStats.successes)
    let submissionAttemptDelta = max(0, endStats.attempts - startStats.attempts)
    let submissionFailureDelta = max(0, endStats.failures - startStats.failures)
    let connectionAttemptDelta = max(0, endStats.connectionAttempts - startStats.connectionAttempts)
    let connectionSuccessDelta = max(
      0,
      endStats.connectionSuccesses - startStats.connectionSuccesses
    )
    let connectionFailureDelta = max(0, endStats.connectionFailures - startStats.connectionFailures)

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: seconds,
      driverKitValueEvents: retained.driverKitValueEvents,
      driverKitReportEvents: retained.driverKitReportEvents,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      userSpaceRequired: true,
      userSpaceStatus: currentUserSpaceStatus(),
      driverKitRequired: driverKitRequired,
      driverKitInputReportDelta: driverKitDelta,
      driverKitSubmissionSuccessDelta: submissionSuccessDelta,
      driverKitSubmissionAttemptDelta: submissionAttemptDelta,
      driverKitSubmissionFailureDelta: submissionFailureDelta,
      driverKitSubmissionLastErrorHex: endStats.lastErrorHex,
      driverKitConnectionAttemptDelta: connectionAttemptDelta,
      driverKitConnectionSuccessDelta: connectionSuccessDelta,
      driverKitConnectionFailureDelta: connectionFailureDelta,
      driverKitLastConnectionErrorHex: endStats.lastConnectionErrorHex,
      driverKitDiscoverySummary: endStats.lastDiscoverySummary
    )
  }

  private func exerciseUserSpaceSelfTest(
    _ userSpace: (any CompatibilityUserSpaceOutputDispatching)?,
    identifier: DeviceIdentifier
  ) async {
    for probe in 0..<4 {
      await userSpace?.dispatch(events: [], from: identifier)
      if probe < 3 { try? await Task.sleep(nanoseconds: 250_000_000) }
    }
  }

  private func runDriverKitProbe(seconds: Int) async -> Int {
    await withTaskGroup(of: Int.self) { group in
      group.addTask { await self.driverKitDispatcher.sendDiagnosticProbe() }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        return 0
      }
      let result = await group.next() ?? 0
      group.cancelAll()
      while await group.next() != nil {}
      return result
    }
  }

  private func waitForSelfTestWindow(seconds: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
  }

}
