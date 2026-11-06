import Foundation

extension DeviceManager {
  /// Starts device detection and input processing.
  public func start() async {
    guard !isStopping else { return }
    isStarted = true
    // A start requested during system sleep runs when the system wakes.
    guard !isSystemSleeping else { return }
    let startGeneration = lifecycleGeneration
    let state = await permissionManager.checkAccess().inputRead
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

  /// Starts the task that checks the host's access state once per second, which starts or ends HID
  /// detection and retries the HID input claims; does nothing while that task runs.
  func startPermissionWatch() {
    guard permissionWatchTask == nil else { return }
    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let currentState = await self.permissionManager.checkAccess().inputRead
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

  /// Re-admits each connected controller of a model in `models`, whose records changed, so it binds
  /// with the current controller records.
  ///
  /// Other controllers keep their sessions.
  ///
  /// Each affected connection is torn down as for a detach and admitted again, but keeps the
  /// user's suspension. With raw-USB detection running, its next poll does this for USB and HID
  /// connections together, so a controller reachable by both picks its route again, and this
  /// returns once they are torn down. Does nothing while stopped or asleep; a later start or wake
  /// reads the current records anyway.
  public func reloadControllerRecords(changing models: Set<ControllerModelID>) async {
    guard isStarted, !isStopping, !isSystemSleeping else { return }
    guard seesController(in: models) else {
      print("[DeviceManager] Controller records changed - no connected controller affected")
      return
    }
    print("[DeviceManager] Controller records changed - re-admitting affected controllers")
    if usbTransportProvider != nil, !detectionTasks.isEmpty {
      pendingRecordReloads.formUnion(models)
      await withCheckedContinuation { recordReloadWaiters.append($0) }
    } else {
      await readmitHIDConnections(changing: models)
    }
  }

  /// Tears down and admits again each current HID connection that OJD tracks and whose model is in
  /// `changed`, including one that yielded to raw USB.
  ///
  /// A device whose native pass-through changed with the records is first admitted again by the
  /// HID backend, which seizes or releases it, and is left out here so it is not admitted twice.
  func readmitHIDConnections(changing changed: Set<ControllerModelID>) async {
    let suspendedConnections = Set(
      suspendedControllerIdentities.compactMap { identifier -> UUID? in
        guard changed.contains(identifier.model) else { return nil }
        return deviceInfos[identifier]?.hidConnectionID
      }
    )
    ownershipCycledHIDConnections.formUnion(suspendedConnections)
    let reevaluated = await hidManager.reevaluateOwnership(of: changed)
    let current = await hidManager.currentConnectionSnapshots()
    // A connection that is still current was not admitted again, so its next disconnect is
    // physical. Without snapshots, no connection can be told apart, so every mark is dropped.
    ownershipCycledHIDConnections.subtract(
      current.map { $0.map(\.connection.connectionID) } ?? Array(suspendedConnections)
    )
    guard let snapshots = current else { return }
    for snapshot in snapshots {
      let connection = snapshot.connection
      guard !isStopping, let model = connection.physicalDevice.model, changed.contains(model),
        !reevaluated.contains(connection.connectionID),
        tracksHIDConnection(connection.connectionID)
      else { continue }
      clearUnboundDevice(.hid(connection.connectionID))
      clearPassThroughDevice(connection.connectionID)
      if yieldedHIDConnections.removeValue(forKey: connection.connectionID) != nil {
        _ = await hidManager.reacquireInputClaim(address: connection.routingAddress)
      }
      let bound = deviceInfos.filter { $0.value.hidConnectionID == connection.connectionID }.keys
      for identifier in bound {
        let suspended = suspendedControllerIdentities.contains(identifier)
        await tearDownHIDDevice(identifier: identifier, connection: connection)
        if suspended { suspendedControllerIdentities.insert(identifier) }
      }
      hidRoleConnections.removeValue(forKey: connection.connectionID)
      guard !isStopping else { return }
      // As in HID detection, a native connection binds inline.
      if connection.physicalDevice.nativePassThrough {
        await handleHIDDeviceConnected(connection: connection, ownership: snapshot.ownership)
      } else {
        scheduleHIDDeviceInitialization(connection: connection, ownership: snapshot.ownership)
      }
    }
  }

  /// Whether OJD tracks the HID connection in any form: bound, unbound, left to macOS, yielded to
  /// raw USB or initializing.
  private func tracksHIDConnection(_ connectionID: UUID) -> Bool {
    deviceInfos.values.contains { $0.hidConnectionID == connectionID }
      || unboundDevices[.hid(connectionID)] != nil || passThroughDevices[connectionID] != nil
      || yieldedHIDConnections[connectionID] != nil
      || hidInitializationTasks.values.contains { $0.connection.connectionID == connectionID }
  }

  /// Whether the manager holds a controller of a model in `models` in any form, such as a
  /// pipeline, an unbound device, a pass-through device or a pending initialization.
  private func seesController(in models: Set<ControllerModelID>) -> Bool {
    let seen = pipelines.keys.map(\.model) + deviceInfos.keys.map(\.model)
    return seen.contains { models.contains($0) }
      || unboundDevices.values.contains {
        models.contains(ControllerModelID(vendorID: $0.vendorID, productID: $0.productID))
      }
      || passThroughDevices.values.contains {
        models.contains(
          ControllerModelID(vendorID: $0.description.vendorID, productID: $0.description.productID)
        )
      }
      || hidInitializationTasks.values.contains {
        guard let model = $0.connection.physicalDevice.model else { return true }
        return models.contains(model)
      }
  }

  /// Restarts detection for a manager that was started before or during sleep.
  public func systemDidWake(session: DeviceManagerSystemPowerEventSession? = nil) async {
    guard session?.isActive ?? true, isSystemSleeping, !isStopping else { return }
    isSystemSleeping = false
    if isStarted { await start() }
  }
}
