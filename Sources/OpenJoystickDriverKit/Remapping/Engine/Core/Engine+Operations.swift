import Foundation

extension RemappingEventEngine {

  /// Processes one source's snapshot with a validated profile.
  ///
  /// The snapshot is diffed against the last one `source` delivered, and the changes drive
  /// `target`, which defaults to `source`. A changed profile first neutralizes the earlier mapping
  /// of the target.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed,
  ///   ``RemappingEventEngineError/faulted`` while faulted,
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails, and
  ///   ``RemappingValidationError`` for a profile that does not validate.
  public func process(
    _ event: ControllerEvent,
    from source: LogicalControllerID,
    into target: LogicalControllerID? = nil,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await process(
      event,
      from: source,
      into: target,
      using: profile,
      at: uptimeNanoseconds,
      requiring: permit
    )
  }

  /// Processes one source's snapshot under an emission permit.
  ///
  /// Behaves like the variant without a permit, but the permit decides admission.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted,
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails, and
  ///   ``RemappingValidationError`` for a profile that does not validate.
  public func process(
    _ event: ControllerEvent,
    from source: LogicalControllerID,
    into target: LogicalControllerID? = nil,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try profile.validate()
    try await commit(requiring: permit) { state in
      state.process(
        event,
        from: source,
        into: target ?? source,
        profile: profile,
        at: uptimeNanoseconds
      )
    }
  }

  /// Forgets the baseline of a stopped source, so its next snapshot is diffed against neutral.
  public func endSource(_ source: LogicalControllerID) async {
    await acquireOperation()
    defer { finishOperation() }
    state.sourceBaselines.removeValue(forKey: source)
  }

  /// Replaces or deactivates the profile for one exact controller.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed,
  ///   ``RemappingEventEngineError/faulted`` while faulted,
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails, and
  ///   ``RemappingValidationError`` for a profile that does not validate.
  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: LogicalControllerID
  ) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await setProfile(profile, for: identifier, requiring: permit)
  }

  /// Replaces or deactivates the profile for one exact controller under an emission permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted,
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails, and
  ///   ``RemappingValidationError`` for a profile that does not validate.
  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try profile?.validate()
    try await commit(requiring: permit) { state in state.setProfile(profile, for: identifier) }
  }

  /// Advances time-driven output to an uptime.
  ///
  /// That covers turbo phases, pulses, sticks, triggers, chord and sequence timers, long-hold and
  /// double-tap timers, and continuous pointer and scroll output.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func tick(at uptimeNanoseconds: UInt64) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await tick(at: uptimeNanoseconds, requiring: permit)
  }

  /// Advances time-driven output to an uptime under an emission permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func tick(
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.tick(at: uptimeNanoseconds) }
  }

  /// Whether any output needs a future tick.
  ///
  /// Held keys and pointer buttons alone need none. A faulted engine reports `false`, because
  /// fail-closed handling clears all mapping state.
  public func hasScheduledOutput() -> Bool { state.hasScheduledOutput }

  /// Returns the motion calibration status of a controller, or `nil` when it has no mapping
  /// session.
  public func motionCalibrationStatus(
    for identifier: LogicalControllerID
  ) -> RemappingMotionCalibrationStatus? { state.motionCalibrationStatus(for: identifier) }

  /// Returns the identifier of the current mapping session of a controller, or `nil` without one.
  ///
  /// A profile replacement or a release ends a session and its identifier.
  public func motionSessionIdentifier(for identifier: LogicalControllerID) -> UUID? {
    state.devices[identifier]?.sessionID
  }

  /// Applies a motion calibration command to a controller and returns the resulting status.
  /// - Throws: ``RemappingMotionCalibrationError`` when the controller is unknown or a start
  ///   request has no baseline, ``RemappingEventEngineError/outputSuspended`` when routing
  ///   admission is closed, ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: LogicalControllerID
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    return try await calibrateMotion(command, for: identifier, requiring: permit)
  }

  /// Applies a motion calibration command to a controller under an emission permit.
  ///
  /// A reset also clears the gyro stick and motion stick outputs. The command and its outputs apply
  /// together or not at all.
  /// - Parameters:
  ///   - command: The calibration command to apply.
  ///   - identifier: The controller to calibrate.
  ///   - permit: The emission permit that admits the resulting output.
  ///   - expectedSessionID: When set, the controller's mapping session must match it.
  /// - Returns: The motion calibration status of the controller after the command.
  /// - Throws: ``RemappingMotionCalibrationError`` when the controller or its expected session is
  ///   unknown or a start request has no baseline,
  ///   ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit,
    expectedSessionID: UUID? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let sessionID = state.devices[identifier]?.sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    guard expectedSessionID == nil || expectedSessionID == sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    await acquireOperation()
    defer { finishOperation() }
    try ensureAvailable()
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    guard state.devices[identifier]?.sessionID == sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    var calibrated = state
    let status = try calibrated.calibrateMotion(command, for: identifier)
    var actions: [RemappingEngineAction] = []
    if command == .reset, var device = calibrated.devices[identifier] {
      actions = device.clearGyroStick()
      calibrated.devices[identifier] = device
      actions += calibrated.clearMotionStick(for: identifier, at: device.lastUptime)
    }
    try await commitUnchecked { candidate in
      candidate = calibrated
      return actions
    }
    return status
  }

  /// Returns the earliest monotonic deadline required by scheduled output, or `nil` when none is.
  ///
  /// Turbo deadlines are exact phase boundaries. Continuous destinations use the caller-owned
  /// cadence because their platform scaling and delivery rate are adapter policy. Arithmetic
  /// saturates at `UInt64.max`.
  /// - Parameters:
  ///   - uptimeNanoseconds: The current monotonic uptime in nanoseconds.
  ///   - continuousIntervalNanoseconds: Interval between ticks of continuous output.
  /// - Returns: The earliest deadline in monotonic nanoseconds, or `nil` when no output is
  ///   scheduled.
  public func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    state.nextScheduledTick(
      after: uptimeNanoseconds,
      continuousIntervalNanoseconds: continuousIntervalNanoseconds
    )
  }

  /// Releases every output owned by one exact controller and forgets its profile.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func releaseAll(for identifier: LogicalControllerID) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await releaseAll(for: identifier, requiring: permit)
  }

  /// Releases every output owned by one exact controller under an emission permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func releaseAll(
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.releaseController(identifier) }
  }

  /// Sets the profile color of a controller through the physical output sink.
  ///
  /// Does nothing when there is no physical output sink. A `nil` color is passed to the sink as
  /// given.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and any error of the physical output
  ///   sink.
  public func setProfileColor(
    _ color: ControllerColor?,
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    await acquireOperation()
    defer { finishOperation() }
    try ensureAvailable()
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    guard let physicalOutputSink else { return }
    try await physicalOutputSink.setProfileColor(color, for: identifier)
  }

  /// Releases every output of every controller and forgets all source baselines.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func drain() async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await drain(requiring: permit)
  }

  /// Releases every output of every controller under an emission permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted,
  ///   ``RemappingEventEngineError/faulted`` while faulted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func drain(requiring permit: RemappingEmissionPermit) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.drain() }
  }

  /// Performs the one terminal neutralization after routing admission has closed permanently.
  ///
  /// A faulted engine recovers first.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing has not terminated, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  public func drainAfterTermination() async throws {
    await acquireOperation()
    defer { finishOperation() }
    guard let lease = emissionBarrier.acquireTerminationLease() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    if faulted { try await recoverUncertainOutputs() }
    try await commitUnchecked { state in state.drain() }
  }

  /// Retries uncertain releases after a sink or permission failure.
  ///
  /// The engine remains faulted if any release fails and cannot emit new presses until recovery
  /// completes.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when routing admission is closed, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a release fails.
  public func recover() async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await recover(requiring: permit)
  }

  /// Retries uncertain releases under an emission permit.
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a release fails.
  public func recover(requiring permit: RemappingEmissionPermit) async throws {
    await acquireOperation()
    defer { finishOperation() }
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    guard faulted else { return }
    try await recoverUncertainOutputs()
  }

  /// Releases the uncertain outputs and clears the fault once every release succeeded.
  private func recoverUncertainOutputs() async throws {
    try await releaseUncertainOutputs()
    faulted = false
  }

  /// Releases every output that may still be held after a failure.
  ///
  /// Keyboard and pointer outputs go first, in release order, and stop at the first failure.
  /// Virtual gamepad devices and physical devices follow.
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when a release fails or a sink is
  ///   missing.
  func releaseUncertainOutputs() async throws {
    var failed = false
    for output in Self.releaseOrder(uncertainHeldOutputs) {
      do {
        try sink.send(output.releaseAction)
        uncertainHeldOutputs.remove(output)
      } catch {
        failed = true
        break
      }
    }
    for identifier in uncertainGamepadDevices.sorted() {
      do {
        guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
        try await gamepadSink.send(.neutral, for: identifier)
        uncertainGamepadDevices.remove(identifier)
      } catch { failed = true }
    }
    for identifier in uncertainPhysicalDevices.sorted() {
      do {
        guard let physicalOutputSink else { throw RemappingEventEngineError.sinkUnavailable }
        try await physicalOutputSink.releaseAll(for: identifier)
        uncertainPhysicalDevices.remove(identifier)
      } catch { failed = true }
    }
    if failed { throw RemappingEventEngineError.sinkUnavailable }
  }

  /// Checks that the engine is not faulted.
  /// - Throws: ``RemappingEventEngineError/faulted``.
  private func ensureAvailable() throws {
    guard !faulted else { throw RemappingEventEngineError.faulted }
  }

  /// Waits until no other operation runs, then marks the engine busy.
  ///
  /// Operations run one at a time, in arrival order, also across suspension points.
  private func acquireOperation() async {
    if !operationInProgress {
      operationInProgress = true
      return
    }
    await withCheckedContinuation { operationWaiters.append($0) }
  }

  /// Ends the running operation and resumes the next waiting one.
  private func finishOperation() {
    guard !operationWaiters.isEmpty else {
      operationInProgress = false
      return
    }
    operationWaiters.removeFirst().resume()
  }

  /// Runs a state transition under a lease for a permit and delivers its actions.
  /// - Throws: ``RemappingEventEngineError/faulted`` while faulted,
  ///   ``RemappingEventEngineError/outputSuspended`` when the permit is not admitted, and
  ///   ``RemappingEventEngineError/sinkUnavailable`` when a sink fails.
  private func commit(
    requiring permit: RemappingEmissionPermit,
    _ transition: (inout RemappingEngineState) -> [RemappingEngineAction]
  ) async throws {
    await acquireOperation()
    defer { finishOperation() }
    try ensureAvailable()
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    try await commitUnchecked(transition)
  }

  /// Delivers the actions of a state transition to the sinks in order.
  ///
  /// The transition runs on a copy of the state, which replaces the state once every action is
  /// delivered. A sink failure fails closed.
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable``.
  private func commitUnchecked(
    _ transition: (inout RemappingEngineState) -> [RemappingEngineAction]
  ) async throws {
    let previous = state
    var candidate = previous
    let actions = transition(&candidate)
    var potentiallyHeld = previous.heldOutputs
    for action in actions {
      do {
        switch action {
        case .system(let systemAction):
          try sink.send(systemAction)
          Self.accountForDelivered(systemAction, in: &potentiallyHeld)
        case .gamepad(let gamepadState, let identifier):
          guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
          heldGamepadDevices.insert(identifier)
          try await gamepadSink.send(gamepadState, for: identifier)
          if gamepadState == .neutral { heldGamepadDevices.remove(identifier) }
        case .physical(let output, let active, let owner, let identifier):
          guard let physicalOutputSink else { throw RemappingEventEngineError.sinkUnavailable }
          try await physicalOutputSink.set(output, active: active, owner: owner, for: identifier)
          if active {
            heldPhysicalOwners[identifier, default: []].insert(owner)
          } else {
            heldPhysicalOwners[identifier]?.remove(owner)
            if heldPhysicalOwners[identifier]?.isEmpty == true {
              heldPhysicalOwners.removeValue(forKey: identifier)
            }
          }
        }
      } catch {
        if case .system(let systemAction) = action {
          Self.accountForUncertain(systemAction, in: &potentiallyHeld)
        }
        if case .physical(_, _, _, let identifier) = action {
          uncertainPhysicalDevices.insert(identifier)
        }
        await failClosed(potentiallyHeld: potentiallyHeld)
        throw RemappingEventEngineError.sinkUnavailable
      }
    }
    state = candidate
  }
}
