import Foundation

struct RemappingMotionLeanChange {
  let direction: RemappingMotionLeanDirection
  let isActive: Bool
}

extension RemappingEngineState {
  mutating func expireMotionStick(
    for identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard let deadline = devices[identifier]?.motionStickDeadline, uptime >= deadline else {
      return []
    }
    return clearMotionStick(for: identifier, at: uptime)
  }

  mutating func clearMotionStick(
    for identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    device.motionStickDeadline = nil
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
  mutating func updateMotionStick(
    _ processed: RemappingProcessedMotion?
  ) -> (actions: [RemappingEngineAction], leanChanges: [RemappingMotionLeanChange]) {
    if processed == nil, motion.latest != nil { return ([], []) }
    guard processed?.deltaTime ?? 0 > 0 else {
      motionStickDeadline = nil
      return (clearMotionSteering(), setLeanStates(left: false, right: false))
    }
    guard let processed, let angle = Self.leanAngle(gravity: processed.fused.gravityG) else {
      motionStickDeadline = nil
      return (clearMotionSteering(), setLeanStates(left: false, right: false))
    }
    if effectiveMotionTuning.lean != nil || effectiveMotionTuning.steering != nil {
      let (deadline, overflow) = lastUptime.addingReportingOverflow(100_000_000)
      motionStickDeadline = overflow ? .max : deadline
    } else {
      motionStickDeadline = nil
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
      if let state = gamepad.update(contribution, for: motionSteeringBindingID) {
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
      wasActive: activeMotionLeans.contains(.left)
    )
    let right = Self.leanIsActive(
      magnitude: max(0, angle),
      threshold: lean.thresholdDegrees,
      hysteresis: lean.hysteresisDegrees,
      wasActive: activeMotionLeans.contains(.right)
    )
    return (actions, setLeanStates(left: left, right: right))
  }

  mutating func clearMotionSteering() -> [RemappingEngineAction] {
    guard let state = gamepad.update(.neutral, for: motionSteeringBindingID) else { return [] }
    return [.gamepad(state, identifier)]
  }

  mutating func clearMotionLeanStates() -> [RemappingMotionLeanChange] {
    setLeanStates(left: false, right: false)
  }

  private mutating func setLeanStates(
    left: Bool,
    right: Bool
  ) -> [RemappingMotionLeanChange] {
    var changes: [RemappingMotionLeanChange] = []
    for (direction, active) in [
      (RemappingMotionLeanDirection.left, left),
      (RemappingMotionLeanDirection.right, right),
    ] {
      let wasActive = activeMotionLeans.contains(direction)
      guard wasActive != active else { continue }
      if active { activeMotionLeans.insert(direction) } else { activeMotionLeans.remove(direction) }
      changes.append(RemappingMotionLeanChange(direction: direction, isActive: active))
    }
    return changes
  }

  private static func leanAngle(gravity: ControllerMotionVector) -> Double? {
    guard gravity.isFinite else { return nil }
    let length = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
    guard length > 1e-9 else { return nil }
    return asin(min(1, max(-1, gravity.x / length))) * 180 / .pi
  }

  private static func leanIsActive(
    magnitude: Double,
    threshold: Double,
    hysteresis: Double,
    wasActive: Bool
  ) -> Bool {
    wasActive ? magnitude > threshold - hysteresis : magnitude >= threshold
  }
}
