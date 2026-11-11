import Foundation

/// A change of one lean direction.
struct RemappingMotionLeanChange {
  /// Direction that changed.
  let direction: RemappingMotionLeanDirection
  /// Whether the direction became active.
  let isActive: Bool
}

extension RemappingEngineState {
  /// Clears tilt steering and lean sources of a controller when the motion stick deadline has
  /// passed.
  mutating func expireMotionStick(
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard let deadline = devices[identifier]?.motion.motionStickDeadline, uptime >= deadline else {
      return []
    }
    return clearMotionStick(for: identifier, at: uptime)
  }

  /// Clears tilt steering and lean sources of a controller.
  mutating func clearMotionStick(
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    device.motion.motionStickDeadline = nil
    var actions = device.clearMotionSteering()
    let changes = device.clearMotionLeanStates()
    devices[identifier] = device
    for change in changes {
      actions += setSource(
        .motionLean(change.direction),
        isActive: false,
        for: identifier,
        at: uptime
      )
    }
    return actions
  }
}

extension RemappingDeviceState {
  /// Updates tilt steering and lean from the gravity of a processed sample.
  ///
  /// Returns the gamepad actions and the lean changes. Without a sample while a baseline exists,
  /// nothing changes. A sample without a time step, or with unusable gravity, clears both. When
  /// lean or steering is configured, the output expires 100 ms after the latest uptime.
  mutating func updateMotionStick(
    _ processed: RemappingProcessedMotion?
  ) -> (actions: [RemappingEngineAction], leanChanges: [RemappingMotionLeanChange]) {
    if processed == nil, motion.motion.latest != nil { return ([], []) }
    guard processed?.deltaTime ?? 0 > 0 else {
      motion.motionStickDeadline = nil
      return (clearMotionSteering(), setLeanStates(left: false, right: false))
    }
    guard let processed, let angle = Self.leanAngle(gravity: processed.fused.gravityG) else {
      motion.motionStickDeadline = nil
      return (clearMotionSteering(), setLeanStates(left: false, right: false))
    }
    if effectiveMotionTuning.lean != nil || effectiveMotionTuning.steering != nil {
      let (deadline, overflow) = lastUptime.addingReportingOverflow(100_000_000)
      motion.motionStickDeadline = overflow ? .max : deadline
    } else {
      motion.motionStickDeadline = nil
    }
    var actions: [RemappingEngineAction] = []
    if let steering = effectiveMotionTuning.steering {
      let magnitude = abs(angle)
      let normalized =
        magnitude <= steering.deadzoneDegrees
        ? 0
        : min(
          1,
          (magnitude - steering.deadzoneDegrees)
            / (steering.fullScaleDegrees - steering.deadzoneDegrees)
        )
      var value = pow(normalized, steering.responseExponent) * (angle < 0 ? -1 : 1)
      if steering.inverted { value = -value }
      let contribution = RemappingGamepadState(axes: [steering.output.axis: value])
      if let state = outputs.gamepad.update(contribution, for: motion.motionSteeringBindingID) {
        actions.append(.gamepad(state, identifier))
      }
    } else {
      actions += clearMotionSteering()
    }

    guard let lean = effectiveMotionTuning.lean else {
      return (actions, setLeanStates(left: false, right: false))
    }
    let left = Self.leanIsActive(
      magnitude: max(0, -angle),
      threshold: lean.thresholdDegrees,
      hysteresis: lean.hysteresisDegrees,
      wasActive: motion.activeMotionLeans.contains(.left)
    )
    let right = Self.leanIsActive(
      magnitude: max(0, angle),
      threshold: lean.thresholdDegrees,
      hysteresis: lean.hysteresisDegrees,
      wasActive: motion.activeMotionLeans.contains(.right)
    )
    return (actions, setLeanStates(left: left, right: right))
  }

  /// Clears the tilt steering contribution and returns the action that neutralizes it.
  mutating func clearMotionSteering() -> [RemappingEngineAction] {
    guard let state = outputs.gamepad.update(.neutral, for: motion.motionSteeringBindingID) else {
      return []
    }
    return [.gamepad(state, identifier)]
  }

  /// Switches every lean direction off and returns the changes.
  mutating func clearMotionLeanStates() -> [RemappingMotionLeanChange] {
    setLeanStates(left: false, right: false)
  }

  /// Sets the lean directions and returns those that changed.
  private mutating func setLeanStates(left: Bool, right: Bool) -> [RemappingMotionLeanChange] {
    var changes: [RemappingMotionLeanChange] = []
    for (direction, active) in [
      (RemappingMotionLeanDirection.left, left), (RemappingMotionLeanDirection.right, right),
    ] {
      let wasActive = motion.activeMotionLeans.contains(direction)
      guard wasActive != active else { continue }
      if active {
        motion.activeMotionLeans.insert(direction)
      } else {
        motion.activeMotionLeans.remove(direction)
      }
      changes.append(RemappingMotionLeanChange(direction: direction, isActive: active))
    }
    return changes
  }

  /// Returns the sideways tilt in degrees from the X component of gravity, or `nil` for unusable
  /// gravity.
  ///
  /// A positive angle leans right.
  private static func leanAngle(gravity: ControllerMotionVector) -> Double? {
    guard gravity.isFinite else { return nil }
    let length = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
    guard length > 1e-9 else { return nil }
    return asin(min(1, max(-1, gravity.x / length))) * 180 / .pi
  }

  /// Whether a lean direction is active.
  ///
  /// It becomes active at the threshold and stays active while the magnitude is above the threshold
  /// minus the hysteresis.
  private static func leanIsActive(
    magnitude: Double,
    threshold: Double,
    hysteresis: Double,
    wasActive: Bool
  ) -> Bool { wasActive ? magnitude > threshold - hysteresis : magnitude >= threshold }
}
