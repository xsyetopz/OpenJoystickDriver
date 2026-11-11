extension RemappingEngineState {
  /// Applies a motion sample to a controller.
  ///
  /// The sample updates tilt steering and the lean sources first. The gyro output then follows the
  /// profile's gyro output mode: the stick modes drive a virtual gamepad stick, and the mouse mode
  /// emits a pointer movement. The gyro output is cleared while it is inactive, and on the first
  /// processed sample after the wait for a baseline.
  mutating func processMotion(
    _ sample: ControllerMotionSample,
    for identifier: LogicalControllerID
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let processed = device.motion.motion.process(sample, tuning: device.effectiveMotionTuning)
    let motionStick = device.updateMotionStick(processed)
    var actions = motionStick.actions
    devices[identifier] = device
    for change in motionStick.leanChanges {
      actions += setSource(
        .motionLean(change.direction),
        isActive: change.isActive,
        for: identifier,
        at: device.lastUptime
      )
    }
    guard var current = devices[identifier] else { return actions }
    guard current.isGyroActive else {
      actions += current.clearGyroStick()
      devices[identifier] = current
      return actions
    }
    if current.motion.gyroAwaitingBaseline, processed != nil {
      current.motion.gyroAwaitingBaseline = false
      actions += current.clearGyroStick()
      devices[identifier] = current
      return actions
    }
    let trackball = current.processTrackball(processed)
    if current.profile.gyroOutput.mode == .leftStick
      || current.profile.gyroOutput.mode == .rightStick
    {
      actions += current.updateGyroStick(processed, velocity: trackball?.velocity)
      devices[identifier] = current
      return actions
    }
    devices[identifier] = current
    guard let processed, processed.deltaTime > 0, current.profile.gyroOutput.mode == .mouse else {
      return actions
    }
    let scale = current.profile.gyroOutput.pointerPointsPerDegree
    // Player/world projections already reverse yaw relative to local controller Y.
    let yawSign = current.effectiveMotionTuning.space == .local ? -1.0 : 1.0
    let yaw = trackball?.yawDegrees ?? processed.tunedGyro.yawDegreesPerSecond * processed.deltaTime
    let pitch =
      trackball?.pitchDegrees ?? processed.tunedGyro.pitchDegreesPerSecond * processed.deltaTime
    let x = yaw * scale * yawSign
    let y = -pitch * scale
    guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return actions }
    actions.append(.system(.pointerDelta(x: x, y: y)))
    return actions
  }
}

extension RemappingDeviceState {
  /// Advances the gyro trackball for a processed sample.
  ///
  /// Returns `nil` without trackball settings, and without a sample. The trackball holds an axis
  /// while its source is active.
  mutating func processTrackball(
    _ processed: RemappingProcessedMotion?
  ) -> RemappingMotionTrackball.Step? {
    guard let settings = profile.gyroOutput.trackball else { return nil }
    guard let processed else {
      if motion.motion.latest == nil { motion.gyroTrackball.reset() }
      return nil
    }
    let held = activeSources.contains(settings.source)
    return motion.gyroTrackball.process(
      processed.tunedGyro,
      deltaTime: processed.deltaTime,
      pitchHeld: held && settings.axes != .yaw,
      yawHeld: held && settings.axes != .pitch,
      decayHalvingsPerSecond: settings.decayHalvingsPerSecond
    )
  }

  /// Whether the gyro output is active, from its activation mode and activation source.
  var isGyroActive: Bool {
    let held = profile.gyroOutput.activationSource.map { activeSources.contains($0) } ?? false
    switch profile.gyroOutput.activationMode {
    case .always: return true
    case .whileHeld: return held
    case .whileReleased: return !held
    case .toggle: return motion.gyroToggleActive
    }
  }

  /// Returns the virtual stick action for the gyro velocity.
  ///
  /// The velocity is divided by the full-stick speed and clamped. A sample without a time step, a
  /// value that is not finite, or a zero value clears the output. Otherwise the output expires 100
  /// ms after the latest uptime.
  mutating func updateGyroStick(
    _ processed: RemappingProcessedMotion?,
    velocity: RemappingGyroProjection? = nil
  ) -> [RemappingEngineAction] {
    guard let processed else { return motion.motion.latest == nil ? clearGyroStick() : [] }
    guard processed.deltaTime > 0 else { return clearGyroStick() }
    let output = profile.gyroOutput
    let yawSign = effectiveMotionTuning.space == .local ? -1.0 : 1.0
    let stickVelocity = velocity ?? processed.tunedGyro
    let x = stickVelocity.yawDegreesPerSecond * yawSign / output.fullStickDegreesPerSecond
    let y = -stickVelocity.pitchDegreesPerSecond / output.fullStickDegreesPerSecond
    guard x.isFinite, y.isFinite else { return clearGyroStick() }
    let horizontal: RemappingAxis = output.mode == .leftStick ? .leftStickX : .rightStickX
    let vertical: RemappingAxis = output.mode == .leftStick ? .leftStickY : .rightStickY
    let contribution = RemappingGamepadState(axes: [
      horizontal: max(-1, min(1, x)), vertical: max(-1, min(1, y)),
    ])
    if x == 0, y == 0 { return clearGyroStick() }
    let (deadline, overflow) = lastUptime.addingReportingOverflow(100_000_000)
    motion.gyroDeadline = overflow ? .max : deadline
    guard let state = outputs.gamepad.update(contribution, for: motion.gyroBindingID) else {
      return []
    }
    return [.gamepad(state, identifier)]
  }

  /// Clears the gyro stick output, its expiry and its trackball, and returns the action that
  /// neutralizes the stick.
  mutating func clearGyroStick() -> [RemappingEngineAction] {
    motion.gyroDeadline = nil
    motion.gyroTrackball.reset()
    guard let state = outputs.gamepad.update(.neutral, for: motion.gyroBindingID) else { return [] }
    return [.gamepad(state, identifier)]
  }
}
