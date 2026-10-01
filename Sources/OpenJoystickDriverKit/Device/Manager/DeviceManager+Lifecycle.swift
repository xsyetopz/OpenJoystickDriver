import Foundation

extension DeviceManager {
  /// Start device detection and input processing.
  public func start() async {
    guard !isStopping else { return }
    isStarted = true
    // A start requested during system sleep runs when the system wakes.
    guard !isSystemSleeping else { return }
    let startGeneration = lifecycleGeneration
    let state = await permissionManager.checkAccess().inputMonitoring
    guard !isStopping, lifecycleGeneration == startGeneration else { return }
    switch state {
    case .unknown, .denied:
      if state == .denied {
        print("[DeviceManager] Input Monitoring denied" + " - running in detect-only mode")
        print(
          "[DeviceManager] Open System Settings" + " > Privacy > Input Monitoring"
            + " to grant access"
        )
      } else {
        print("[DeviceManager] Input Monitoring not yet granted" + " - running in detect-only mode")
        print(
          "[DeviceManager] Use the app's Request Access action" + " to show the native macOS prompt"
        )
      }
    case .granted: print("[DeviceManager] Input Monitoring granted")
    }

    if usbTransportProvider != nil, detectionTasks.isEmpty {
      detectionTasks = [Task { await self.runUSBDetection() }]
    } else if usbTransportProvider == nil {
      detectionTasks = []
    }
    await ensureHIDDetectionState(for: state)
    guard !isStopping, lifecycleGeneration == startGeneration else { return }
    startPermissionWatch()

    print("[DeviceManager] Started" + " - dual detection active")
  }

  func startPermissionWatch() {
    guard permissionWatchTask == nil else { return }
    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let currentState = await self.permissionManager.checkAccess().inputMonitoring
        await self.ensureHIDDetectionState(for: currentState)
        await self.retryHIDInputClaims()
        try? await Task.sleep(nanoseconds: devicePermissionWatchNanoseconds)
      }
    }
  }

  /// Tears down every controller session as if each controller were unplugged.
  ///
  /// Controllers re-attach through ordinary hot-plug detection after `systemDidWake`.
  public func systemWillSleep(session: DeviceManagerSystemPowerEventSession? = nil) async {
    guard session?.isActive ?? true, !isSystemSleeping else { return }
    // Recorded even before the first start() or during stop(), so a later start() waits for wake.
    isSystemSleeping = true
    guard isStarted, !isStopping else { return }
    isStopping = true
    await tearDownControllerSessions()
    isStopping = false
    print("[DeviceManager] Suspended for system sleep")
  }

  /// Re-admits every controller so each binds with the current controller records, when a
  /// controller OJD sees has a vendor and product ID in `identities`, whose records changed.
  ///
  /// Sessions are torn down as for system sleep and detection starts again, so connected
  /// controllers re-attach through hot-plug detection. Does nothing while stopped or asleep; a
  /// later start or wake reads the current records anyway.
  public func reloadControllerRecords(changing identities: Set<ControllerIdentity>) async {
    guard isStarted, !isStopping, !isSystemSleeping else { return }
    guard seesController(in: identities) else {
      print("[DeviceManager] Controller records changed - no connected controller affected")
      return
    }
    isStopping = true
    await tearDownControllerSessions()
    isStopping = false
    print("[DeviceManager] Controller records changed - re-admitting controllers")
    await start()
  }

  private func seesController(in identities: Set<ControllerIdentity>) -> Bool {
    let changed = Set(identities.map { [$0.vendorID, $0.productID] })
    let seen = pipelines.keys.map(\.controllerIdentity) + deviceInfos.keys.map(\.controllerIdentity)
    return seen.contains { changed.contains([$0.vendorID, $0.productID]) }
      || unboundDevices.values.contains { changed.contains([$0.vendorID, $0.productID]) }
      || passThroughDevices.values.contains {
        changed.contains([$0.description.vendorID, $0.description.productID])
      }
      || hidInitializationTasks.values.contains {
        let device = $0.connection.physicalDevice
        guard let vendorID = device.vendorID, let productID = device.productID else { return true }
        return changed.contains([vendorID, productID])
      }
  }

  /// Restarts detection for a manager that was started before or during sleep.
  public func systemDidWake(session: DeviceManagerSystemPowerEventSession? = nil) async {
    guard session?.isActive ?? true, isSystemSleeping, !isStopping else { return }
    isSystemSleeping = false
    if isStarted { await start() }
  }
}
