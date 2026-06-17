import Foundation
import IOKit
import IOKit.hid

/// Sends HID reports to the DriverKit virtual gamepad via `IOHIDDeviceSetReport`.
///
/// The daemon finds the virtual device by VID/PID through IOHIDManager,
/// then sends output reports. The dext's `setReport` override
/// relays them as input reports via `handleReport`.
///
/// If ``connect()`` returns `false`, ``dispatch(events:from:)`` auto-retries
/// on every call until the dext loads.
public final class DextOutputDispatcher: OutputDispatcher, @unchecked Sendable {

  /// Posted when DriverKit injection is unstable (typically during sysext replacement/upgrade).
  public static let dextUnstableNotification = Notification.Name("OpenJoystickDriver.DextUnstable")

  // MARK: - Thread safety
  //
  // @unchecked Sendable safety:
  // - `reportLock` guards all mutable report state (buttons, sticks, triggers, hat)
  // - `connectionLock` guards `hidDevice` and `hidManager`
  // - `suppressOutput` is only written from the main actor (XPC handler)

  // MARK: - OutputDispatcher

  /// When true, report injection is suppressed (e.g. during developer packet capture).
  public var suppressOutput = false

  // MARK: - HID device connection

  /// Identity of the virtual gamepad presented to the OS.
  let profile: VirtualDeviceProfile
  let format: any VirtualGamepadReportFormat
  var hidDevice: IOHIDDevice?
  var hidManager: IOHIDManager?
  let connectionLock = NSLock()
  var enabled: Bool = true
  var nextAutoRetryConnectNs: UInt64 = 0
  var autoRetryBackoffNs: UInt64 = 250_000_000  // 250ms
  var lastConnectionLostLogNs: UInt64 = 0

  // MARK: - Optional exclusive-seize (Compatibility mode)

  let seizeLock = NSLock()
  var seizedDevice: IOHIDDevice?
  var seizedManager: IOHIDManager?
  var compatibilitySeizeRequested = false
  var seizeRetryScheduled = false

  // MARK: - Stability tracking

  let stabilityLock = NSLock()
  var failureTimestamps: [UInt64] = []
  var lastUnstablePost: UInt64 = 0

  // MARK: - Output stats (for diagnostics)

  let statsLock = NSLock()
  var setReportAttempts: Int = 0
  var setReportSuccesses: Int = 0
  var setReportFailures: Int = 0
  var lastSetReportError: IOReturn?
  var connectionAttempts: Int = 0
  var connectionSuccesses: Int = 0
  var connectionFailures: Int = 0
  var lastConnectionError: IOReturn?
  var lastDiscoverySummary: String?

  // MARK: - Report state

  let reportLock = NSLock()
  var buttons: UInt32 = 0
  var leftStickX: Int16 = 0
  var leftStickY: Int16 = 0
  var rightStickX: Int16 = 0
  var rightStickY: Int16 = 0
  var leftTrigger: Int16 = 0
  var rightTrigger: Int16 = 0
  var hat: GamepadHIDDescriptor.Hat = .neutral

  static let relayMagic: [UInt8] = [0x4F, 0x4A]  // "OJ"
  // MARK: - Init / deinit

  /// Creates a new DextOutputDispatcher.
  ///
  /// - Parameters:
  ///   - profile: Virtual device identity used for HID device matching.
  public init(profile: VirtualDeviceProfile = .openJoystickDriver) {
    self.profile = profile
    self.format = OJDGenericGamepadFormat()
  }

  deinit { closeDevice() }

  // MARK: - OutputDispatcher

  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    guard !suppressOutput else { return }
    guard connectionLock.withLock({ enabled }) else { return }

    var device = connectionLock.withLock { hidDevice }

    if device == nil {
      let now = DispatchTime.now().uptimeNanoseconds
      let shouldAttempt = connectionLock.withLock { now >= nextAutoRetryConnectNs }
      if shouldAttempt {
        if let (newDevice, mgr) = findDevice(openOptions: IOOptionBits(kIOHIDOptionsTypeNone)) {
          device = newDevice
          print("[DextOutputDispatcher] Auto-retry connected to virtual gamepad")
          connectionLock.withLock {
            hidDevice = newDevice
            hidManager = mgr
            nextAutoRetryConnectNs = 0
            autoRetryBackoffNs = 250_000_000
          }
        } else {
          connectionLock.withLock {
            nextAutoRetryConnectNs = now &+ autoRetryBackoffNs
            autoRetryBackoffNs = min(autoRetryBackoffNs &* 2, 5_000_000_000)  // cap at 5s
          }
        }
      }
    }
    guard let device else { return }

    let reports = reportLock.withLock { () -> [(CFIndex, [UInt8])] in
      for event in events { applyEvent(event, deadzone: 0.15) }
      let secondaryReports = events.compactMap { xboxGuideReport(for: $0) }
      return [primaryOutputReport()] + secondaryReports
    }

    var lastResult: IOReturn = kIOReturnSuccess
    for (reportID, payload) in reports {
      var report = payload
      let result = report.withUnsafeMutableBytes { ptr -> IOReturn in
        guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
        return IOHIDDeviceSetReport(
          device,
          kIOHIDReportTypeOutput,
          reportID,
          base.assumingMemoryBound(to: UInt8.self),
          ptr.count
        )
      }
      recordSetReportResult(result)
      if result != kIOReturnSuccess { lastResult = result }
    }

    // kIOReturnNotOpen (0xe00002cd): device handle went stale during sysext replacement.
    // The dext process cycles through device instances on crash/rematch; reconnecting
    // picks up the latest instance.
    if lastResult == kIOReturnNotAttached || lastResult == kIOReturnNoDevice
      || lastResult == IOReturn(bitPattern: 0xe000_02cd)
    {
      let now = DispatchTime.now().uptimeNanoseconds
      let shouldLog = connectionLock.withLock { () -> Bool in
        // Rate-limit to avoid log spam and "inefficient" kills.
        if now &- lastConnectionLostLogNs < 10_000_000_000 { return false }
        lastConnectionLostLogNs = now
        return true
      }
      if shouldLog {
        print("[DextOutputDispatcher] Connection lost (\(lastResult)); will reconnect")
      }
      recordFailure(now: now)
      closeDevice()
      connectionLock.withLock { nextAutoRetryConnectNs = now &+ autoRetryBackoffNs }
    } else if lastResult != kIOReturnSuccess {
      // Keep this quiet; repeated failures are handled via stats + fallback mode.
    }
  }

  public func outputStatsSnapshot() -> XPCDriverKitOutputStats {
    statsLock.withLock {
      let err = lastSetReportError.map { String(format: "0x%08x", UInt32(bitPattern: $0)) }
      return XPCDriverKitOutputStats(
        attempts: setReportAttempts,
        successes: setReportSuccesses,
        failures: setReportFailures,
        lastErrorHex: err,
        connectionAttempts: connectionAttempts,
        connectionSuccesses: connectionSuccesses,
        connectionFailures: connectionFailures,
        lastConnectionErrorHex: lastConnectionError.map {
          String(format: "0x%08x", UInt32(bitPattern: $0))
        },
        lastDiscoverySummary: lastDiscoverySummary
      )
    }
  }

  func recordDiscoverySummary(_ summary: String) {
    statsLock.withLock { lastDiscoverySummary = String(summary.prefix(500)) }
  }

  func recordConnectionAttempt() { statsLock.withLock { connectionAttempts += 1 } }

  func recordConnectionResult(_ result: IOReturn) {
    statsLock.withLock {
      if result == kIOReturnSuccess {
        connectionSuccesses += 1
      } else {
        connectionFailures += 1
        lastConnectionError = result
      }
    }
  }

  func recordFailure(now: UInt64) {
    // Consider the dext unstable if we see lots of abort/not-open errors in a short window.
    // This commonly happens while the OS is replacing the system extension.
    let windowNs: UInt64 = 5_000_000_000  // 5s
    let threshold = 20
    let cooldownNs: UInt64 = 10_000_000_000  // 10s

    stabilityLock.withLock {
      failureTimestamps.append(now)

      // Prune old events.
      let cutoff = now &- windowNs
      if failureTimestamps.count > 512 {
        failureTimestamps.removeFirst(failureTimestamps.count - 512)
      }
      while let first = failureTimestamps.first, first < cutoff { failureTimestamps.removeFirst() }

      if failureTimestamps.count >= threshold && (now &- lastUnstablePost) > cooldownNs {
        lastUnstablePost = now
        NotificationCenter.default.post(name: Self.dextUnstableNotification, object: nil)
      }
    }
  }

  func recordSetReportResult(_ result: IOReturn) {
    // DriverKit's HID relay can return kIOReturnAborted after delivering the input report
    // through handleReport(). Self-test verifies delivery via input value/report deltas, so
    // count this as accepted for UI health instead of surfacing a false failure.
    let accepted = result == kIOReturnSuccess || result == kIOReturnAborted
    statsLock.withLock {
      setReportAttempts += 1
      if accepted {
        setReportSuccesses += 1
      } else {
        setReportFailures += 1
        lastSetReportError = result
      }
    }
  }
}
