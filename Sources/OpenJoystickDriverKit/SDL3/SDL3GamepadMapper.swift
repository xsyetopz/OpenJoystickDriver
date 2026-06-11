import Foundation

public enum SDL3GamepadMapper {
  private static let buttonMap: [SDL3GamepadButton: Button] = [
    .south: .a,
    .east: .b,
    .west: .x,
    .north: .y,
    .leftShoulder: .leftBumper,
    .rightShoulder: .rightBumper,
    .leftStick: .leftStick,
    .rightStick: .rightStick,
    .back: .back,
    .start: .start,
    .guide: .guide,
  ]

  public static func events(
    previous: SDL3GamepadSnapshot,
    current: SDL3GamepadSnapshot
  ) -> [ControllerEvent] {
    var events: [ControllerEvent] = []

    for sdlButton in SDL3GamepadButton.allCases {
      guard let button = buttonMap[sdlButton] else { continue }
      let wasPressed = previous.buttons.contains(sdlButton)
      let isPressed = current.buttons.contains(sdlButton)
      if wasPressed != isPressed {
        events.append(isPressed ? .buttonPressed(button) : .buttonReleased(button))
      }
    }

    let previousLeftX = normalizeStick(previous.axes[.leftX] ?? 0)
    let previousLeftY = normalizeStick(previous.axes[.leftY] ?? 0)
    let leftX = normalizeStick(current.axes[.leftX] ?? 0)
    let leftY = normalizeStick(current.axes[.leftY] ?? 0)
    if changed(previousLeftX, leftX) || changed(previousLeftY, leftY) {
      events.append(.leftStickChanged(x: leftX, y: leftY))
    }

    let previousRightX = normalizeStick(previous.axes[.rightX] ?? 0)
    let previousRightY = normalizeStick(previous.axes[.rightY] ?? 0)
    let rightX = normalizeStick(current.axes[.rightX] ?? 0)
    let rightY = normalizeStick(current.axes[.rightY] ?? 0)
    if changed(previousRightX, rightX) || changed(previousRightY, rightY) {
      events.append(.rightStickChanged(x: rightX, y: rightY))
    }

    let leftTrigger = normalizeTrigger(current.axes[.leftTrigger] ?? 0)
    if changed(normalizeTrigger(previous.axes[.leftTrigger] ?? 0), leftTrigger) {
      events.append(.leftTriggerChanged(leftTrigger))
    }

    let rightTrigger = normalizeTrigger(current.axes[.rightTrigger] ?? 0)
    if changed(normalizeTrigger(previous.axes[.rightTrigger] ?? 0), rightTrigger) {
      events.append(.rightTriggerChanged(rightTrigger))
    }

    if let dpad = dpadDirection(from: current.buttons),
       dpad != dpadDirection(from: previous.buttons) {
      events.append(.dpadChanged(dpad))
    }

    return events
  }

  private static func normalizeStick(_ value: Int16) -> Float {
    if value < 0 { return max(-1, Float(value) / 32768.0) }
    return min(1, Float(value) / 32767.0)
  }

  private static func normalizeTrigger(_ value: Int16) -> Float {
    max(0, min(1, Float(value) / 32767.0))
  }

  private static func changed(_ lhs: Float, _ rhs: Float) -> Bool { abs(lhs - rhs) > 0.0001 }

  private static func dpadDirection(from buttons: Set<SDL3GamepadButton>) -> DpadDirection? {
    let up = buttons.contains(.dpadUp)
    let down = buttons.contains(.dpadDown)
    let left = buttons.contains(.dpadLeft)
    let right = buttons.contains(.dpadRight)
    switch (up, down, left, right) {
    case (false, false, false, false): return .neutral
    case (true, false, false, false): return .north
    case (true, false, false, true): return .northEast
    case (false, false, false, true): return .east
    case (false, true, false, true): return .southEast
    case (false, true, false, false): return .south
    case (false, true, true, false): return .southWest
    case (false, false, true, false): return .west
    case (true, false, true, false): return .northWest
    default: return .neutral
    }
  }
}
