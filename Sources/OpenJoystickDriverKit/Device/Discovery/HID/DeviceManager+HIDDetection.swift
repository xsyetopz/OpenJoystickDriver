import Foundation

/// A bound HID controller that HID teardown may remove, with the state that teardown must find
/// unchanged.
private struct HIDTeardownCandidate {
  /// The identifier of the controller.
  let identifier: LogicalControllerID
  /// The device information at the time the candidate was listed.
  let info: DeviceManager.DeviceInfo
  /// The physical device of the connection.
  let physicalDevice: PhysicalDevice
  /// The ID of the HID connection that the controller was admitted on.
  let connectionID: UUID
  /// The pipeline that ran at that time; nil when none ran.
  let pipeline: DevicePipeline?
}

extension DeviceManager {
  // MARK: - HID detection (class 0x03)

  /// Starts HID detection when Input Monitoring is granted, and ends it and removes the HID
  /// pipelines when the permission is unknown or denied.
  ///
  /// Does nothing while the manager stops, or when detection already runs.
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

  /// Reads the events of the HID backend for one detection session until the session ends.
  ///
  /// A native pass-through connection binds inline; any other connection initializes in its own
  /// task. While the manager stops, events are dropped but the session stays open for teardown
  /// output.
  private func runHIDDetection(sessionID: UUID) async {
    defer { finishHIDDetection(sessionID: sessionID) }
    guard hidDetectionSessionID == sessionID, !isStopping, !Task.isCancelled else { return }
    print("[DeviceManager] HID detection started" + " (class 0x03)")
    let events = await hidManager.deviceEvents()
    guard hidDetectionSessionID == sessionID, !isStopping, !Task.isCancelled else { return }
    // Events that arrive while one is handled are taken together, so an input report that a later
    // report of its controller already follows is known before its slow publication starts.
    let batches = EventBatches<HIDDeviceEvent>()
    let reader = Task.detached {
      for await event in events { batches.append(event) }
      batches.finish()
    }
    defer {
      reader.cancel()
      batches.finish()
    }
    while let batch = await batches.next() {
      let followed = Self.inputReportsFollowedByLaterReport(in: batch)
      for (index, event) in batch.enumerated() {
        guard hidDetectionSessionID == sessionID, !Task.isCancelled else { return }
        // Teardown sends neutral and shutdown reports through this still-open session, then
        // cancels the task; returning here instead would close the session under those writes.
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
        case .inputReport(let address, let connectionID, _, let data):
          await routeHIDInputReport(
            address: address,
            connectionID: connectionID,
            data: data,
            laterReportQueued: followed.contains(index)
          )
        case .ownershipChanged, .inputValue: await handleHIDEvent(event)
        case .accessFailure:
          await handleHIDEvent(event)
          return
        }
      }
    }
  }

  /// The indices of the input reports in `batch` that a later report of the same connection
  /// follows, with no other event between them.
  static func inputReportsFollowedByLaterReport(in batch: [HIDDeviceEvent]) -> Set<Int> {
    struct Source: Hashable {
      let address: ControllerConnectionAddress
      let connectionID: UUID
    }
    var laterReports: Set<Source> = []
    var followed: Set<Int> = []
    for (index, event) in batch.enumerated().reversed() {
      guard case .inputReport(let address, let connectionID, _, _) = event else {
        laterReports.removeAll()
        continue
      }
      let source = Source(address: address, connectionID: connectionID)
      if !laterReports.insert(source).inserted { followed.insert(index) }
    }
    return followed
  }

  /// Holds the events that arrive while their consumer is busy, so it takes them all at once and
  /// in order.
  final class EventBatches<Element: Sendable>: Sendable {
    /// The state of the batches: the events not yet taken, whether they finished, and the consumer
    /// that waits.
    private struct State: Sendable {
      /// The events appended since the last take.
      var pending: [Element] = []
      /// Whether ``finish()`` ran.
      var finished = false
      /// The consumer that waits in ``next()``; nil when none waits.
      var waiter: CheckedContinuation<[Element]?, Never>?
    }

    /// The state, behind a lock.
    private let state = Locked(State())

    /// The events appended since the last call, waiting while there are none; nil once `finish()`
    /// ran and every event was taken.
    ///
    /// Cancelling the calling task finishes the batches.
    func next() async -> [Element]? {
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          let ready = state.withLock { state -> [Element]?? in
            if !state.pending.isEmpty {
              defer { state.pending.removeAll() }
              return .some(state.pending)
            }
            if state.finished { return .some(nil) }
            state.waiter = continuation
            return nil
          }
          if let ready { continuation.resume(returning: ready) }
        }
      } onCancel: {
        finish()
      }
    }

    /// Whether a consumer is suspended in `next()` with nothing to take.
    var hasWaitingConsumer: Bool { state.withLock { $0.waiter != nil } }

    /// Adds `event` after every pending one; ignored once finished.
    func append(_ event: Element) {
      let waiter = state.withLock { state -> CheckedContinuation<[Element]?, Never>? in
        guard !state.finished else { return nil }
        guard let waiter = state.waiter else {
          state.pending.append(event)
          return nil
        }
        state.waiter = nil
        return waiter
      }
      waiter?.resume(returning: [event])
    }

    /// Ends the batches: `next()` returns the pending events, then nil.
    func finish() {
      let waiter = state.withLock { state -> CheckedContinuation<[Element]?, Never>? in
        state.finished = true
        defer { state.waiter = nil }
        return state.waiter
      }
      waiter?.resume(returning: nil)
    }
  }

  /// Ends the bookkeeping of the detection session `sessionID` when it is still the current one.
  func finishHIDDetection(sessionID: UUID) {
    guard hidDetectionSessionID == sessionID else { return }
    hidDetectionSessionID = nil
    hidDetectionTask = nil
  }

  /// Initializes `connection` in its own task under its initialization key and cancels the pending
  /// initialization under that key.
  ///
  /// Does nothing while the manager stops.
  func scheduleHIDDeviceInitialization(
    connection: HIDDeviceConnection,
    ownership: HIDInputOwnership
  ) {
    guard !isStopping else { return }
    let key = hidInitializationKey(for: connection)
    hidInitializationTasks.removeValue(forKey: key)?.task.cancel()
    let task = Task { [weak self] in
      guard let self else { return }
      await handleHIDDeviceConnected(connection: connection, ownership: ownership)
      await finishHIDDeviceInitialization(connection: connection)
    }
    hidInitializationTasks[key] = HIDDeviceInitialization(connection: connection, task: task)
  }

  /// Ends the initialization record of `connection` when it is still the one under its key, and
  /// removes the device information that an aborted replacement left behind.
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
    case .ownershipChanged(let address, let ownership):
      await updateHIDOwnership(ownership, address: address)
    case .accessFailure(let failure):
      print("[DeviceManager] HID access stream failed: \(String(reflecting: failure))")
      await removeHIDPipelines()
    case .disconnected(let connection): await handleHIDDeviceDisconnected(connection: connection)
    case .inputReport(let loc, let connectionID, _, let data):
      await routeHIDInputReport(address: loc, connectionID: connectionID, data: data)
    case .inputValue(let loc, let connectionID, let value):
      await routeHIDElementValue(address: loc, connectionID: connectionID, value: value)
    }
  }

  /// Whether the change of ownership of a refused or failed seize admits the pipeline again: from
  /// another client's ownership to anything else, and from a failed acquisition to an exclusive
  /// seize.
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
    var addresses: Set<ControllerConnectionAddress> = []
    for (identifier, info) in deviceInfos {
      guard case .hid = info.discoverySource, info.physicalDevice?.nativePassThrough != true,
        info.hidInputOwnership == .ownedByAnotherClient
          || info.hidInputOwnership == .acquisitionFailed, let pipeline = pipelines[identifier],
        !pipeline.observesOnly, !suspendedControllerIdentities.contains(identifier),
        let address = identifier.hidRoutingAddress,
        !unboundHIDClaims.values.contains(where: {
          $0.routingAddress == address && $0.isReleased
        })
      else { continue }
      addresses.insert(address)
    }
    for address in addresses.sorted() {
      await hidManager.retryInputClaim(address: address)
    }
  }

  /// Applies the HID input ownership of a routing address to every HID controller there.
  ///
  /// A seize that another client took stops the pipeline after its physical outputs are
  /// neutralized. A refused or failed seize that succeeds admits the controller again with a fresh
  /// parser, so controls held before the access loss are not replayed. A native pass-through
  /// controller is skipped, because the ownership describes OJD's seize of other interfaces.
  func updateHIDOwnership(
    _ ownership: HIDInputOwnership,
    address: ControllerConnectionAddress
  ) async {
    let identifiers = deviceInfos.keys.filter { $0.hidRoutingAddress == address }
    for identifier in identifiers {
      // A location's ownership describes OJD's seize of other interfaces, never a native one.
      guard let info = deviceInfos[identifier], case .hid = info.discoverySource,
        info.physicalDevice?.nativePassThrough != true
      else { continue }
      deviceInfos[identifier]?.hidInputOwnership = ownership
      if info.hidInputOwnership != ownership { notifyServiceStatusChanged() }
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
              routingAddress: address
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

  /// Removes every HID pipeline and its device information, after it clears the unbound,
  /// pass-through and yielded records.
  ///
  /// Pending initializations are cancelled and awaited first. The physical outputs of a pipeline
  /// are neutralized before it stops. A controller that a replacement changed in the meantime is
  /// left alone.
  private func removeHIDPipelines() async {
    clearUnboundHIDDevices()
    clearPassThroughDevices()
    hidRoleConnections.removeAll()
    let hidIdentifiers = Set(
      pipelines.keys.filter { deviceInfos[$0]?.discoverySource.requiresInputRead == true }
        + deviceInfos.keys.filter {
          deviceInfos[$0]?.discoverySource.requiresInputRead == true
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

  /// Whether `candidate` still matches the state it was listed with: its device information, no
  /// pending initialization, and the same pipeline or none.
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

  /// Whether the device information of `candidate` still names its HID connection and physical
  /// device.
  private func isCurrentHIDTeardownInfo(_ candidate: HIDTeardownCandidate) -> Bool {
    guard let info = deviceInfos[candidate.identifier], case .hid = info.discoverySource else {
      return false
    }
    return info.hidConnectionID == candidate.connectionID
      && info.physicalDevice == candidate.physicalDevice
  }

  /// Removes the device information, output queue and periodic output task that an aborted
  /// replacement of `connection` left behind.
  ///
  /// Does nothing while the manager stops, or while the information still names the connection, a
  /// pipeline runs, or an initialization is pending.
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
