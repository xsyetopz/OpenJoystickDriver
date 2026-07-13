import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

final class ForegroundConsumerHIDManagerState: @unchecked Sendable {
  private let lock = NSLock()
  private let manager: IOHIDManager
  private var isOpen = false

  init() {
    manager = IOHIDManagerCreate(
      kCFAllocatorDefault,
      IOOptionBits(kIOHIDOptionsTypeNone)
    )
    IOHIDManagerSetDeviceMatching(manager, nil)
  }

  deinit {
    lock.withLock {
      if isOpen {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
      }
    }
  }

  func withOpenManager<T>(_ body: (IOHIDManager) -> T) -> T? {
    lock.withLock {
      if !isOpen {
        let result = IOHIDManagerOpen(
          manager,
          IOOptionBits(kIOHIDOptionsTypeNone)
        )
        guard result == kIOReturnSuccess else { return nil }
        isOpen = true
      }
      return body(manager)
    }
  }
}

/// Gates controller output unless the frontmost app is one of the current
/// OpenJoystickDriver virtual-device consumers.
final class ForegroundConsumerOutputMonitor: @unchecked Sendable {
  private let deviceManager: DeviceManager
  private let compatibilityRouteHandler:
    @Sendable (String?, Set<String>, Set<String>, String?) async -> Void
  private let pollIntervalNanoseconds: UInt64
  private let burstPollIntervalNanoseconds: UInt64
  private let burstPollDurationNanoseconds: UInt64
  private let stateLock = NSLock()
  private var periodicTask: Task<Void, Never>?
  private var burstTask: Task<Void, Never>?
  private var burstPollingDeadlineNanoseconds: UInt64 = 0
  private var activationObserver: NSObjectProtocol?
  private var activityTracker = ForegroundConsumerActivityTracker()
  private var cachedFrontmostBundleRoot: String?
  private var lastAppliedAllowOutput: Bool?
  private var lastAppliedFrontmostBundleRoot: String?
  private var lastAppliedConsumerBundleRoots: Set<String> = []
  private var lastAppliedObservedBundleRoots: Set<String> = []
  private var lastAppliedActiveRouteToken: String?
  static let consumerHIDManagerState = ForegroundConsumerHIDManagerState()

  init(
    deviceManager: DeviceManager,
    compatibilityRouteHandler:
      @escaping @Sendable (String?, Set<String>, Set<String>, String?) async -> Void = {
        _, _, _, _ in
      },
    pollIntervalNanoseconds: UInt64 = 1_000_000_000,
    burstPollIntervalNanoseconds: UInt64 = 100_000_000,
    burstPollDurationNanoseconds: UInt64 = 3_000_000_000
  ) {
    self.deviceManager = deviceManager
    self.compatibilityRouteHandler = compatibilityRouteHandler
    self.pollIntervalNanoseconds = pollIntervalNanoseconds
    self.burstPollIntervalNanoseconds = burstPollIntervalNanoseconds
    self.burstPollDurationNanoseconds = burstPollDurationNanoseconds
  }

  func stop() {
    let tasksAndObserver = stateLock.withLock {
      let tasks = (periodicTask, burstTask)
      periodicTask = nil
      burstTask = nil
      burstPollingDeadlineNanoseconds = 0
      let observer = activationObserver
      activationObserver = nil
      return (tasks.0, tasks.1, observer)
    }
    tasksAndObserver.0?.cancel()
    tasksAndObserver.1?.cancel()
    if let observer = tasksAndObserver.2 {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  func start() {
    stateLock.withLock {
      guard periodicTask == nil else { return }
      periodicTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
          await self.evaluateAndApply()
        }
      }
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      self.updateFrontmostBundleRoot(Self.frontmostBundleRootPath())
      Task { await self.evaluateAndApply() }

      let center = NSWorkspace.shared.notificationCenter
      activationObserver = center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let self else { return }
        let app =
          notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        self.updateFrontmostBundleRoot(Self.bundleRootPath(for: app))
        self.scheduleBurstPolling()
      }
    }
  }

  private func scheduleBurstPolling() {
    stateLock.withLock {
      burstPollingDeadlineNanoseconds = max(
        burstPollingDeadlineNanoseconds,
        DispatchTime.now().uptimeNanoseconds &+ burstPollDurationNanoseconds
      )
      guard burstTask == nil else { return }
      burstTask = Task { [weak self] in
        guard let self else { return }
        while !Task.isCancelled {
          await self.evaluateAndApply()

          let shouldContinue = self.stateLock.withLock { () -> Bool in
            DispatchTime.now().uptimeNanoseconds < burstPollingDeadlineNanoseconds
          }
          guard shouldContinue else {
            self.stateLock.withLock {
              burstTask = nil
              burstPollingDeadlineNanoseconds = 0
            }
            return
          }

          try? await Task.sleep(nanoseconds: self.burstPollIntervalNanoseconds)
        }

        self.stateLock.withLock {
          burstTask = nil
          burstPollingDeadlineNanoseconds = 0
        }
      }
    }
  }

  private func evaluateAndApply() async {
    let frontmostBundleRoot = stateLock.withLock { cachedFrontmostBundleRoot }
    let now = DispatchTime.now().uptimeNanoseconds
    let consumerClients = autoreleasepool {
      Self.consumerClientSamples()
    }
    let observedBundleRoots = Set(
      consumerClients
        .filter { $0.isOpened && !$0.isSuspended }
        .map(\.bundleRootPath)
    )
    let consumerBundleRoots = stateLock.withLock {
      activityTracker.consumerBundleRootPaths(
        frontmostBundleRootPath: frontmostBundleRoot,
        clients: consumerClients,
        now: now
      )
    }
    let activeRouteToken = ForegroundConsumerRouteSelection.activeRouteToken(
      frontmostBundleRootPath: frontmostBundleRoot,
      effectiveConsumerBundleRoots: consumerBundleRoots,
      clients: consumerClients
    )
    let policyAllowsOutput = ForegroundConsumerAccessPolicy.allowsOutput(
      frontmostBundleRootPath: frontmostBundleRoot,
      consumerBundleRootPaths: consumerBundleRoots
    )
    let allowOutput = policyAllowsOutput

    let needsApply = stateLock.withLock { () -> Bool in
      let changed =
        lastAppliedAllowOutput != allowOutput
        || lastAppliedFrontmostBundleRoot != frontmostBundleRoot
        || lastAppliedConsumerBundleRoots != consumerBundleRoots
        || lastAppliedObservedBundleRoots != observedBundleRoots
        || lastAppliedActiveRouteToken != activeRouteToken
      guard changed else { return false }
      lastAppliedAllowOutput = allowOutput
      lastAppliedFrontmostBundleRoot = frontmostBundleRoot
      lastAppliedConsumerBundleRoots = consumerBundleRoots
      lastAppliedObservedBundleRoots = observedBundleRoots
      lastAppliedActiveRouteToken = activeRouteToken
      return true
    }

    guard needsApply else { return }

    await compatibilityRouteHandler(
      frontmostBundleRoot,
      consumerBundleRoots,
      observedBundleRoots,
      activeRouteToken
    )

    if allowOutput {
      if consumerBundleRoots.isEmpty {
        print(
          "[ForegroundConsumerOutputMonitor] Output active "
            + "(no consumer apps holding OJD virtual device)"
        )
      } else if let frontmostBundleRoot {
        let observedLabel = Self.bundleLabelList(observedBundleRoots)
        let effectiveLabel = Self.bundleLabelList(consumerBundleRoots)
        let routeLabel = activeRouteToken ?? "none"
        print(
          "[ForegroundConsumerOutputMonitor] Output active for frontmost consumer: "
            + "\(URL(fileURLWithPath: frontmostBundleRoot).lastPathComponent)"
            + " route=\(routeLabel)"
            + (observedBundleRoots == consumerBundleRoots
              ? ""
              : " effective=[\(effectiveLabel)] observed=[\(observedLabel)]")
        )
      } else {
        print("[ForegroundConsumerOutputMonitor] Output active")
      }
    } else {
      let frontmostLabel =
        frontmostBundleRoot.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "none"
      let consumersLabel = Self.bundleLabelList(consumerBundleRoots)
      let observedLabel = Self.bundleLabelList(observedBundleRoots)
      let routeLabel = activeRouteToken ?? "none"
      print(
        "[ForegroundConsumerOutputMonitor] Output gated; frontmost=\(frontmostLabel) "
          + "consumers=[\(consumersLabel)] route=\(routeLabel)"
          + (observedBundleRoots == consumerBundleRoots ? "" : " observed=[\(observedLabel)]")
      )
    }

    await deviceManager.setExternalOutputAllowed(allowOutput)
  }

  @MainActor
  private static func frontmostBundleRootPath() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return bundleRootPath(for: app)
  }

  private func updateFrontmostBundleRoot(_ bundleRoot: String?) {
    stateLock.withLock {
      cachedFrontmostBundleRoot = bundleRoot
    }
  }
}
