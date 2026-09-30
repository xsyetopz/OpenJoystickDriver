import Foundation

extension DeviceManager {
  func notifyControllerInventoryChanged() {
    NotificationCenter.default.post(name: .ojdControllerInventoryDidChange, object: nil)
  }

  /// Stop all detection and pipelines.
  public func stop() async {
    // Sleep is system state; a stopped manager still waits for wake before a new start() runs.
    isStarted = false
    suspendedControllerIdentities.removeAll()
    guard !isStopping else { return }
    isStopping = true
    await tearDownControllerSessions()
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
    isStopping = false
  }

  /// Cancels detection and tears down every controller as if it were unplugged.
  ///
  /// Callers set `isStopping` first so in-flight admissions and startup work abandon their
  /// controllers instead of registering them.
  func tearDownControllerSessions() async {
    lifecycleGeneration &+= 1

    let pendingPermissionWatch = permissionWatchTask
    permissionWatchTask = nil
    pendingPermissionWatch?.cancel()

    for task in hidPeriodicOutputTasks.values { task.cancel() }
    hidPeriodicOutputTasks = [:]
    for task in rumbleStopTasks.values { task.cancel() }
    rumbleStopTasks = [:]
    rumbleStopTokens.removeAll()
    for task in detectionTasks { task.cancel() }
    detectionTasks = []

    await pendingPermissionWatch?.value

    let pendingHIDInitializations = Array(hidInitializationTasks.values)
    for initialization in pendingHIDInitializations { initialization.task.cancel() }
    hidInitializationTasks = [:]
    for initialization in pendingHIDInitializations { await initialization.task.value }
    permissionWatchTask?.cancel()
    permissionWatchTask = nil
    for pipeline in pipelines.values { await pipeline.acceptOnlyTeardownOutput() }
    // Pending output is dropped before teardown queues each controller's neutralization.
    for queue in hidOutputQueues.values { queue.cancelAll() }
    await ControllerTeardownOutput.$isActive.withValue(true) {
      for (identifier, pipeline) in pipelines {
        await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
        if let locationID = identifier.locationID {
          await sendHIDDeactivationWritesIfNeeded(pipeline: pipeline, locationID: locationID)
        }
        await pipeline.stop()
      }
    }
    // HID detection owns the backend session, so it closes only after the reports above.
    let pendingHIDDetection = hidDetectionTask
    hidDetectionTask = nil
    pendingHIDDetection?.cancel()
    await pendingHIDDetection?.value
    pipelines = [:]
    for task in rumbleStopTasks.values { task.cancel() }
    rumbleStopTasks = [:]
    rumbleStopTokens.removeAll()
    let hadDeviceInfo =
      !deviceInfos.isEmpty || !unboundDevices.isEmpty || !passThroughDevices.isEmpty
    deviceInfos.removeAll()
    hidRoleConnections.removeAll()
    unboundDevices.removeAll()
    unboundHIDClaims.removeAll()
    yieldedHIDConnections.removeAll()
    passThroughDevices.removeAll()
    for identifier in Array(hidOutputQueues.keys) { retireOutputQueue(for: identifier) }
    physicalOutputOwnership.removeAll()
    lastPhysicalHIDOutputNanoseconds = [:]
    if hadDeviceInfo { notifyControllerInventoryChanged() }
    // A drained retired queue has nothing left for a new queue to wait behind.
    for (identifier, queue) in retiredHIDOutputQueues {
      await queue.drain()
      if retiredHIDOutputQueues[identifier] === queue {
        retiredHIDOutputQueues.removeValue(forKey: identifier)
      }
    }
  }

  /// Enables or suppresses application-facing virtual output for every active pipeline.
  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    for pipeline in pipelines.values { await pipeline.setExternalOutputAllowed(allowed) }
  }
}
