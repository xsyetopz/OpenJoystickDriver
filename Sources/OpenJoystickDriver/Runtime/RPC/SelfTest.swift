import CoreHID
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
  private static let probeDelayNanoseconds: UInt64 = 250_000_000

  private final class SelfTestCounter {
    let lock = NSLock()
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

      let serial = strProp(kIOHIDSerialNumberKey as String) ?? strProp("SerialNumber")
      let location = intProp(kIOHIDLocationIDKey as String)
      let isUserSpace =
        UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
          == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)

      guard isUserSpace else { return }
      lock.withLock {
        switch kind {
        case .value: userSpaceValueEvents += 1
        case .report: userSpaceReportEvents += 1
        }
      }
    }
  }

  func runVirtualDeviceSelfTestInternal(seconds: Int) async
    -> ApplicationServiceVirtualDeviceSelfTestPayload
  {
    if #available(macOS 15, *) { return await runCoreHIDSelfTest(seconds: seconds) }
    return await runIOHIDSelfTest(seconds: seconds)
  }

  @available(macOS 15, *) private func runCoreHIDSelfTest(seconds: Int) async
    -> ApplicationServiceVirtualDeviceSelfTestPayload
  {
    let observer = CoreHIDSelfTestObserver()
    await observer.start()
    try? await Task.sleep(for: .milliseconds(100))
    let identifier = await selfTestIdentifier()
    let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
    async let exercise: Void = exerciseUserSpaceSelfTest(userSpace, identifier: identifier)
    async let window: Void = waitForSelfTestWindow(seconds: seconds)
    _ = await (exercise, window)
    let counts = await observer.stop()
    return ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: seconds,
      userSpaceValueEvents: counts.values,
      userSpaceReportEvents: counts.reports,
      userSpaceRequired: true,
      userSpaceStatus: currentUserSpaceStatus()
    )
  }

  @available(macOS, introduced: 10.15, obsoleted: 15.0) private func runIOHIDSelfTest(seconds: Int)
    async -> ApplicationServiceVirtualDeviceSelfTestPayload
  {
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

    let syntheticIdentifier = await selfTestIdentifier()
    let userSpace = userSpaceLock.withLock { userSpaceDispatcher }
    async let userSpaceExercise: Void = exerciseUserSpaceSelfTest(
      userSpace,
      identifier: syntheticIdentifier
    )
    async let observationWindow: Void = waitForSelfTestWindow(seconds: seconds)
    _ = await (userSpaceExercise, observationWindow)

    IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

    let retained = Unmanaged<SelfTestCounter>.fromOpaque(counterPtr).takeRetainedValue()
    return ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: seconds,
      userSpaceValueEvents: retained.userSpaceValueEvents,
      userSpaceReportEvents: retained.userSpaceReportEvents,
      userSpaceRequired: true,
      userSpaceStatus: currentUserSpaceStatus()
    )
  }

  private func selfTestIdentifier() async -> DeviceIdentifier {
    await deviceManager.connectedDeviceIdentifiers().first
      ?? DeviceIdentifier(
        vendorID: 0x4F4A,
        productID: 0x5445,
        serialNumber: "OpenJoystickDriver-SelfTest"
      )
  }

  private func exerciseUserSpaceSelfTest(
    _ userSpace: (any CompatibilityUserSpaceOutputDispatching)?,
    identifier: DeviceIdentifier
  ) async {
    for probe in 0..<4 {
      await userSpace?.dispatch(events: [], from: identifier)
      if probe < 3 { try? await Task.sleep(nanoseconds: Self.probeDelayNanoseconds) }
    }
  }

  private func waitForSelfTestWindow(seconds: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds) * Self.nanosecondsPerSecond)
  }

}

@available(macOS 15, *) private actor CoreHIDSelfTestObserver {
  private var managerTask: Task<Void, Never>?
  private var deviceTasks: [UInt64: Task<Void, Never>] = [:]
  private var valueEvents = 0
  private var reportEvents = 0

  func start() {
    let manager = HIDDeviceManager()
    managerTask = Task { [weak self] in
      let criteria = [
        HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.gamepad)),
        HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.joystick))
      ]
      do {
        for try await notification in await manager.monitorNotifications(matchingCriteria: criteria)
        {
          if Task.isCancelled { break }
          guard case .deviceMatched(let reference) = notification else { continue }
          await self?.add(reference)
        }
      } catch {}
    }
  }

  func stop() -> (values: Int, reports: Int) {
    managerTask?.cancel()
    managerTask = nil
    deviceTasks.values.forEach { $0.cancel() }
    deviceTasks.removeAll()
    return (valueEvents, reportEvents)
  }

  private func add(_ reference: HIDDeviceClient.DeviceReference) async {
    guard deviceTasks[reference.deviceID] == nil,
      let client = HIDDeviceClient(deviceReference: reference),
      UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(await client.serialNumber)
    else { return }
    let task = Task { [weak self] in
      let elements = await client.elements.filter { $0.type == .input }
      do {
        for try await notification in await client.monitorNotifications(
          reportIDsToMonitor: [HIDReportID.allReports],
          elementsToMonitor: elements
        ) {
          if Task.isCancelled { break }
          switch notification {
          case .inputReport: await self?.recordReport()
          case .elementUpdates(let values): await self?.recordValues(values.count)
          case .deviceRemoved: return
          case .deviceSeized, .deviceUnseized: break
          @unknown default: break
          }
        }
      } catch {}
    }
    deviceTasks[reference.deviceID] = task
  }

  private func recordReport() { reportEvents += 1 }
  private func recordValues(_ count: Int) { valueEvents += count }
}
