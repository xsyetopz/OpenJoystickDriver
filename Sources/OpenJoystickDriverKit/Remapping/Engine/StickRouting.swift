import Foundation

extension RemappingEngineState {
  mutating func processAdvancedStick(
    _ source: RemappingStickSource,
    x: Float,
    y: Float,
    for identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier],
      let mapping = device.profile.stickMappings.first(where: { $0.source == source })
    else { return [] }
    var stick = device.sticks[source] ?? RemappingStickRuntime(mapping: mapping)
    let output = stick.update(x: Double(x), y: Double(y), at: uptime)
    let actions = device.stickActions(output, bindingID: stick.bindingID)
    device.sticks[source] = stick
    devices[identifier] = device
    return actions
  }
}

extension RemappingDeviceState {
  mutating func advanceSticks(at uptime: UInt64) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for source in RemappingStickSource.allCases {
      guard var stick = sticks[source] else { continue }
      actions += stickActions(stick.advance(at: uptime), bindingID: stick.bindingID)
      sticks[source] = stick
    }
    return actions
  }

  mutating func stickActions(
    _ output: RemappingStickRuntimeOutput,
    bindingID: UUID
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    if output.pointerDelta.x.isFinite, output.pointerDelta.y.isFinite,
      output.pointerDelta != .zero
    {
      actions.append(.system(.pointerDelta(x: output.pointerDelta.x, y: output.pointerDelta.y)))
    }
    if output.scrollLines.x.isFinite, output.scrollLines.y.isFinite,
      output.scrollLines != .zero
    {
      actions.append(
        .system(.scrollDelta(deltaX: output.scrollLines.x, deltaY: output.scrollLines.y))
      )
    }
    let contribution = RemappingGamepadState(axes: output.virtualAxes)
    if let state = gamepad.update(contribution, for: bindingID) {
      actions.append(.gamepad(state, identifier))
    }
    return actions
  }
}
