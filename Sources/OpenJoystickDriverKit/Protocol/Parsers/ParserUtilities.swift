import Foundation

/// Named normalization strategies for unsigned 8-bit HID axes centered at 128.
enum HIDAxisNormalizationStrategy {
  case unsigned8CenteredSymmetric128(deadzone: Float)
  case unsigned8CenteredFullScale127(deadzone: Float)

  func normalize(_ raw: UInt8) -> Float {
    switch self {
    case .unsigned8CenteredSymmetric128(let deadzone):
      let normalized = (Float(raw) - 128) / 128
      return abs(normalized) < deadzone ? 0 : normalized
    case .unsigned8CenteredFullScale127(let deadzone):
      let centered = Float(raw) - 128
      let divisor: Float = centered >= 0 ? 127 : 128
      let normalized = centered / divisor
      return abs(normalized) < deadzone ? 0 : max(-1, min(1, normalized))
    }
  }
}

/// Compares previous and current button bytes against a mapping table,
/// returning press/release events for any bits that changed.
func diffButtons(prev: UInt8, curr: UInt8, mapping: [(UInt8, Button)]) -> [ControllerEvent] {
  var events: [ControllerEvent] = []
  for (bit, button) in mapping {
    let wasPressed = (prev & bit) != 0
    let isPressed = (curr & bit) != 0
    if !wasPressed && isPressed {
      events.append(.buttonPressed(button))
    } else if wasPressed && !isPressed {
      events.append(.buttonReleased(button))
    }
  }
  return events
}
