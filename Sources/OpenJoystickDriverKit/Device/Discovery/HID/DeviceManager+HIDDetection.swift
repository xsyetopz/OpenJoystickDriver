import Foundation

private struct HIDTeardownCandidate {
  let identifier: DeviceIdentifier
  let info: DeviceManager.DeviceInfo
  let physicalDevice: PhysicalDevice
  let connectionID: UUID
  let pipeline: DevicePipeline?
}

extension DeviceManager {
  // MARK: - HID detection (class 0x03)

  func ensureHIDDetectionState(for state: PermissionManager.AccessState) async {
    guard !isStopping else { return }
    switch state {
    case .granted:
      guard hidDetectionTask == nil else { return }
      let sessionID = UUID()
      hidDetectionSessionID = sessionID
      hidDetectionTask = Task { await self.runHIDDetection(sessionID: sessionID) }
    case .unknown, .denied:
      let task = hidDetectionTask
      hidDetectionTask = nil
      hidDetectionSessionID = nil
      task?.cancel()
      await removeHIDPipelines()
    }
  }

  private func runHIDDetection(sessionID: UUID) async {
    defer { finishHIDDetection(sessionID: sessionID) }
    guard hidDetectionSessionID == sessionID, !isStopping, !Task.isCancelled else { return }
    print("[DeviceManager] HID detection started" + " (class 0x03)")
    let events = await hidManager.deviceEvents()
    guard hidDetectionSessionID == sessionID, !isStopping, !Task.isCancelled else { return }
    for await event in events {
      guard hidDetectionSessionID == sessionID, !Task.isCancelled else { return }
      // Teardown sends neutral and shutdown reports through this still-open session, then cancels
      // the task; returning here instead would close the session under those writes.
      guard !isStopping else { continue }
      switch event {
      case .connected(let connection, _) where connection.physicalDevice.nativePassThrough:
        // A native connection binds inline, so a later sibling's initialization at its location
        // cannot cancel it; it sends no startup output to wait on.
        await handleHIDEvent(event)
      case .connected(let connection, let ownership):
        scheduleHIDDeviceInitialization(connection: connection, ownership: ownership)
      case .disconnected(let connection):
        let key = hidInitializationKey(for: connection)
        if hidInitializationTasks[key]?.connection.connectionID == connection.connectionID {
          hidInitializationTasks.removeValue(forKey: key)?.task.cancel()
        }
        await handleHIDEvent(event)
      case .ownershipChanged, .inputReport, .inputValue: await handleHIDEvent(event)
      case .accessFailure:
        await handleHIDEvent(event)
        return
      }
    }
  }

  func finishHIDDetection(sessionID: UUID) {
    guard hidDetectionSessionID == sessionID else { return }
    hidDetectionSessionID = nil
    hidDetectionTask = nil
  }

  func scheduleHIDDeviceInitialization(
    connection: HIDDeviceConnection,
    ownership: HIDInputOwnership
  ) {
    guard !isStopping else { return }
    let key = hidInitializationKey(for: connection)
    hidInitializationTasks.removeValue(forKey: key)?.task.cancel()
    let task = Task { [weak self] in
      guard let self else { return }
      await self.handleHIDDeviceConnected(connection: connection, ownership: ownership)
      await self.finishHIDDeviceInitialization(connection: connection)
    }
    hidInitializationTasks[key] = HIDDeviceInitialization(connection: connection, task: task)
  }

  func finishHIDDeviceInitialization(connection: HIDDeviceConnection) {
    let key = hidInitializationKey(for: connection)
    if hidInitializationTasks[key]?.connection.connectionID == connection.connectionID {
      hidInitializationTasks.removeValue(forKey: key)
    }
    guard hidInitializationTasks[key] == nil else { return }
    removeOrphanedHIDInfo(after: connection)
  }

  /// Handles backend events in their delivered order, including ownership before input.
  func handleHIDEvent(_ event: HIDDeviceEvent) async {
    guard !isStopping else { return }
    switch event {
    case .connected(let connection, let ownership):
      await handleHIDDeviceConnected(connection: connection, ownership: ownership)
    case .ownershipChanged(let locationID, let ownership):
      await updateHIDOwnership(ownership, locationID: locationID)
    case .accessFailure(let failure):
      print("[DeviceManager] HID access stream failed: \(String(reflecting: failure))")
      await removeHIDPipelines()
    case .disconnected(let connection): await handleHIDDeviceDisconnected(connection: connection)
    case .inputReport(let loc, let connectionID, _, let data):
      await routeHIDInputReport(locationID: loc, connectionID: connectionID, data: data)
    case .inputValue(let loc, let connectionID, let value):
      await routeHIDElementValue(locationID: loc, connectionID: connectionID, value: value)
    }
  }

  /// Whether a seize that was refused or failed and now differs restarts the pipeline.
  private static func readmitsHIDPipeline(
    from old: HIDInputOwnership,
    to new: HIDInputOwnership
  ) -> Bool {
    switch old {
    case .ownedByAnotherClient: new != .ownedByAnotherClient
    case .acquisitionFailed: new == .exclusive
    default: false
    }
  }

  /// Asks the backend to seize again for each bound, active, non-native HID controller that
  /// lacks its seize and whose claim was not released on purpose.
  func retryHIDInputClaims() async {
    var locationIDs: Set<UInt32> = []
    for (identifier, info) in deviceInfos {
      guard case .hid = info.discoverySource, info.physicalDevice?.nativePassThrough != true,
        info.hidInputOwnership == .ownedByAnotherClient
          || info.hidInputOwnership == .acquisitionFailed, let pipeline = pipelines[identifier],
        !pipeline.observesOnly, !suspendedControllerIdentities.contains(identifier),
        let locationID = identifier.locationID,
        !unboundHIDClaims.values.contains(where: {
          $0.routingLocationID == locationID && $0.isReleased
        })
      else { continue }
      locationIDs.insert(locationID)
    }
    for locationID in locationIDs.sorted() {
      await hidManager.retryInputClaim(locationID: locationID)
    }
  }

  func updateHIDOwnership(_ ownership: HIDInputOwnership, locationID: UInt32) async {
    let identifiers = deviceInfos.keys.filter { $0.locationID == locationID }
    for identifier in identifiers {
      // A location's ownership describes OJD's seize of other interfaces, never a native one.
      guard let info = deviceInfos[identifier], case .hid = info.discoverySource,
        info.physicalDevice?.nativePassThrough != true
      else { continue }
      deviceInfos[identifier]?.hidInputOwnership = ownership
      if ownership == .ownedByAnotherClient, info.hidInputOwnership != .ownedByAnotherClient {
        if let pipeline = pipelines[identifier] {
          await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
          await pipeline.stop()
        }
      } else if Self.readmitsHIDPipeline(from: info.hidInputOwnership, to: ownership) {
        // A fresh parser and normalized state prevent replaying controls held before access loss.
        if let physicalDevice = info.physicalDevice, let connectionID = info.hidConnectionID {
          if let stale = pipelines.removeValue(forKey: identifier) { await stale.stop() }
          await handleHIDDeviceConnected(
            connection: HIDDeviceConnection(
              connectionID: connectionID,
              physicalDevice: physicalDevice,
              routingLocationID: locationID
            ),
            ownership: ownership
          )
          continue
        }
      }
      if let listener = dispatcher as? any ControllerInputOwnershipListener {
        await listener.controllerInputOwnershipChanged(ownership, for: identifier)
      }
    }
  }

  private func removeHIDPipelines() async {
    clearUnboundHIDDevices()
    clearPassThroughDevices()
    hidRoleConnections.removeAll()
    let hidIdentifiers = Set(
      pipelines.keys.filter { deviceInfos[$0]?.discoverySource.requiresInputMonitoring == true }
        + deviceInfos.keys.filter {
          deviceInfos[$0]?.discoverySource.requiresInputMonitoring == true
        }
    )
    let candidates = hidIdentifiers.compactMap { identifier -> HIDTeardownCandidate? in
      guard let info = deviceInfos[identifier], case .hid = info.discoverySource,
        let physicalDevice = info.physicalDevice, let connectionID = info.hidConnectionID
      else { return nil }
      return HIDTeardownCandidate(
        identifier: identifier,
        info: info,
        physicalDevice: physicalDevice,
        connectionID: connectionID,
        pipeline: pipelines[identifier]
      )
    }
    let pendingInitializations = Array(hidInitializationTasks.values)
    for initialization in pendingInitializations { initialization.task.cancel() }
    hidInitializationTasks = [:]
    for initialization in pendingInitializations { await initialization.task.value }

    for candidate in candidates {
      let identifier = candidate.identifier
      guard isCurrentHIDTeardownCandidate(candidate) else { continue }
      // Only this connection's queue is removed below, never one a replacement has installed.
      let outputQueue = physicalOutputQueue(for: identifier)
      if let pipeline = candidate.pipeline, pipelines[identifier] === pipeline {
        pipelines.removeValue(forKey: identifier)
        hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
        // Pending output never reaches a disconnected controller; neutralization queues after.
        hidOutputQueues[identifier]?.cancelAll()
        await neutralizePhysicalOutputs(
          for: identifier,
          pipeline: pipeline,
          detachedInfo: candidate.info
        )
        await pipeline.stop()
      } else {
        // A replacement can remove this pipeline while teardown awaits initialization. The
        // matching DeviceInfo is still ours to clear if that replacement has since aborted.
        await candidate.pipeline?.stop()
      }
      guard let key = hidInitializationKey(for: identifier, connectionID: candidate.connectionID),
        isCurrentHIDTeardownInfo(candidate), pipelines[identifier] == nil,
        hidInitializationTasks[key] == nil
      else { continue }
      hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
      retireOutputQueue(for: identifier, expected: outputQueue)
      discardPhysicalOutputs(for: identifier)
      deviceInfos.removeValue(forKey: identifier)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
      print("[DeviceManager] HID pipeline removed: \(identifier)")
    }
  }

  private func isCurrentHIDTeardownCandidate(_ candidate: HIDTeardownCandidate) -> Bool {
    guard isCurrentHIDTeardownInfo(candidate) else { return false }
    guard
      let key = hidInitializationKey(
        for: candidate.identifier,
        connectionID: candidate.connectionID
      ), hidInitializationTasks[key] == nil
    else { return false }
    guard let current = pipelines[candidate.identifier] else { return true }
    guard let expected = candidate.pipeline else { return false }
    return expected === current
  }

  private func isCurrentHIDTeardownInfo(_ candidate: HIDTeardownCandidate) -> Bool {
    guard let info = deviceInfos[candidate.identifier], case .hid = info.discoverySource else {
      return false
    }
    return info.hidConnectionID == candidate.connectionID
      && info.physicalDevice == candidate.physicalDevice
  }

  private func removeOrphanedHIDInfo(after connection: HIDDeviceConnection) {
    guard !isStopping,
      let identifier = hidIdentifier(
        for: connection,
        role: protocolDriverRegistry.hidConnectionRole(of: connection.physicalDevice)
      )
    else { return }
    guard let info = deviceInfos[identifier], case .hid = info.discoverySource,
      info.hidConnectionID != connection.connectionID, pipelines[identifier] == nil,
      hidInitializationTasks[hidInitializationKey(for: connection)] == nil
    else { return }
    hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
    retireOutputQueue(for: identifier)
    discardPhysicalOutputs(for: identifier)
    deviceInfos.removeValue(forKey: identifier)
    lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
    print("[DeviceManager] Aborted HID replacement left stale state: \(identifier)")
  }
}
