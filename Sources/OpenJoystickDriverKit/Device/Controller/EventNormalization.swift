import Foundation

struct ControllerEventNormalizationResult: Equatable, Sendable {
  let events: [ControllerEvent]
  let suppressedEventCount: Int
  let adjustedAnalogValueCount: Int
}

enum ControllerEventNormalizer {
  static func normalize(_ events: [ControllerEvent], from currentState: DeviceInputState)
    -> ControllerEventNormalizationResult
  {
    var adjustedAnalogValueCount = 0
    let sanitized = events.map { event in
      sanitize(
        event,
        currentState: currentState,
        adjustedAnalogValueCount: &adjustedAnalogValueCount
      )
    }
    let nextState = currentState.applying(events: sanitized)
    let normalized = currentState.transitionEvents(to: nextState)
    return ControllerEventNormalizationResult(
      events: normalized,
      suppressedEventCount: max(0, events.count - normalized.count),
      adjustedAnalogValueCount: adjustedAnalogValueCount
    )
  }

  private static func sanitize(
    _ event: ControllerEvent,
    currentState: DeviceInputState,
    adjustedAnalogValueCount: inout Int
  ) -> ControllerEvent {
    switch event {
    case .leftStickChanged(let x, let y):
      return .leftStickChanged(
        x: sanitize(
          x,
          range: -1...1,
          fallback: currentState.leftStickX,
          adjustedCount: &adjustedAnalogValueCount
        ),
        y: sanitize(
          y,
          range: -1...1,
          fallback: currentState.leftStickY,
          adjustedCount: &adjustedAnalogValueCount
        )
      )
    case .rightStickChanged(let x, let y):
      return .rightStickChanged(
        x: sanitize(
          x,
          range: -1...1,
          fallback: currentState.rightStickX,
          adjustedCount: &adjustedAnalogValueCount
        ),
        y: sanitize(
          y,
          range: -1...1,
          fallback: currentState.rightStickY,
          adjustedCount: &adjustedAnalogValueCount
        )
      )
    case .leftTriggerChanged(let value):
      return .leftTriggerChanged(
        sanitize(
          value,
          range: 0...1,
          fallback: currentState.leftTrigger,
          adjustedCount: &adjustedAnalogValueCount
        )
      )
    case .rightTriggerChanged(let value):
      return .rightTriggerChanged(
        sanitize(
          value,
          range: 0...1,
          fallback: currentState.rightTrigger,
          adjustedCount: &adjustedAnalogValueCount
        )
      )
    case .buttonPressed, .buttonReleased, .dpadChanged: return event
    }
  }

  private static func sanitize(
    _ value: Float,
    range: ClosedRange<Float>,
    fallback: Float,
    adjustedCount: inout Int
  ) -> Float {
    guard value.isFinite else {
      adjustedCount += 1
      return fallback
    }
    let clamped = min(max(value, range.lowerBound), range.upperBound)
    if clamped != value { adjustedCount += 1 }
    return clamped
  }
}

extension DeviceInputState {
  func transitionEvents(to next: DeviceInputState) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let currentButtons = Set(pressedButtons)
    let nextButtons = Set(next.pressedButtons)

    for button in Button.allCases where !isDpadButton(button) {
      let wasPressed = currentButtons.contains(button.rawValue)
      let isPressed = nextButtons.contains(button.rawValue)
      if wasPressed != isPressed {
        events.append(isPressed ? .buttonPressed(button) : .buttonReleased(button))
      }
    }

    if currentDpadDirection() != next.currentDpadDirection() {
      events.append(.dpadChanged(next.currentDpadDirection()))
    }
    if leftStickX != next.leftStickX || leftStickY != next.leftStickY {
      events.append(.leftStickChanged(x: next.leftStickX, y: next.leftStickY))
    }
    if rightStickX != next.rightStickX || rightStickY != next.rightStickY {
      events.append(.rightStickChanged(x: next.rightStickX, y: next.rightStickY))
    }
    if leftTrigger != next.leftTrigger { events.append(.leftTriggerChanged(next.leftTrigger)) }
    if rightTrigger != next.rightTrigger { events.append(.rightTriggerChanged(next.rightTrigger)) }

    return events
  }

  private func isDpadButton(_ button: Button) -> Bool {
    switch button {
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return true
    default: return false
    }
  }
}
