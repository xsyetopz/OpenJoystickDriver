import Foundation

extension RemappingEngineState {
  /// Feeds a stick sample to its stick runtime and returns the output actions.
  ///
  /// Returns no actions when the profile has no mapping for the stick.
  mutating func processAdvancedStick(
    _ source: RemappingStickSource,
    x: Float,
    y: Float,
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier],
      let mapping = device.profile.stickMappings.first(where: { $0.source == source })
    else { return [] }
    var stick = device.analog.sticks[source] ?? RemappingStickRuntime(mapping: mapping)
    let output = stick.update(x: Double(x), y: Double(y), at: uptime)
    let actions = device.stickActions(output, bindingID: stick.bindingID)
    device.analog.sticks[source] = stick
    devices[identifier] = device
    return actions
  }
}

extension RemappingDeviceState {
  /// Advances every stick runtime of a controller to an uptime and returns the output actions.
  mutating func advanceSticks(at uptime: UInt64) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for source in RemappingStickSource.allCases {
      guard var stick = analog.sticks[source] else { continue }
      actions += stickActions(stick.advance(at: uptime), bindingID: stick.bindingID)
      analog.sticks[source] = stick
    }
    return actions
  }

  /// Turns the output of a stick runtime into pointer, scroll and virtual gamepad actions.
  ///
  /// Non-finite and zero pointer and scroll movement is dropped.
  mutating func stickActions(
    _ output: RemappingStickRuntimeOutput,
    bindingID: UUID
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    if output.pointerDelta.x.isFinite, output.pointerDelta.y.isFinite, output.pointerDelta != .zero
    {
      actions.append(.system(.pointerDelta(x: output.pointerDelta.x, y: output.pointerDelta.y)))
    }
    if output.scrollLines.x.isFinite, output.scrollLines.y.isFinite, output.scrollLines != .zero {
      actions.append(
        .system(.scrollDelta(deltaX: output.scrollLines.x, deltaY: output.scrollLines.y))
      )
    }
    let contribution = RemappingGamepadState(axes: output.virtualAxes)
    if let state = outputs.gamepad.update(contribution, for: bindingID) {
      actions.append(.gamepad(state, identifier))
    }
    return actions
  }
}
