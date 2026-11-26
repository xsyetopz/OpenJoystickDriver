import Foundation

/// Direction of the d-pad.
public enum RemappingDpadDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// Up.
  case up = "DpadUp"
  /// Down.
  case down = "DpadDown"
  /// Left.
  case left = "DpadLeft"
  /// Right.
  case right = "DpadRight"
}

/// A stick axis, a trigger or a pointer axis of the control vocabulary; the raw value is its
/// control id.
///
/// The pointer axes are sources only: the virtual gamepad has no pointer to output.
public enum RemappingAxis: String, Codable, CaseIterable, Hashable, Sendable {
  /// Left stick horizontal axis.
  case leftStickX = "LeftStickX"
  /// Left stick vertical axis.
  case leftStickY = "LeftStickY"
  /// Right stick horizontal axis.
  case rightStickX = "RightStickX"
  /// Right stick vertical axis.
  case rightStickY = "RightStickY"
  /// Left trigger.
  case leftTrigger = "LeftTrigger"
  /// Right trigger.
  case rightTrigger = "RightTrigger"
  /// Horizontal axis of a pointing device.
  case pointerX = "PointerX"
  /// Vertical axis of a pointing device.
  case pointerY = "PointerY"

  /// The control this axis is.
  public var control: Control {
    switch self {
    case .leftStickX: .leftStickX
    case .leftStickY: .leftStickY
    case .rightStickX: .rightStickX
    case .rightStickY: .rightStickY
    case .leftTrigger: .leftTrigger
    case .rightTrigger: .rightTrigger
    case .pointerX: .pointerX
    case .pointerY: .pointerY
    }
  }

  /// Whether this is a pointer axis.
  public var isPointer: Bool { self == .pointerX || self == .pointerY }
}

/// Half of an axis range.
public enum RemappingAxisDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// The deflection below the center.
  case negative = "Negative"
  /// The deflection above the center.
  case positive = "Positive"
}

/// Modifier key held together with a keyboard key.
public enum RemappingKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
  /// The Meta key (Command on macOS).
  case meta = "Meta"
  /// The Control key.
  case control = "Control"
  /// The Alt key (Option on macOS).
  case alt = "Alt"
  /// The Shift key.
  case shift = "Shift"
}

/// Button of the pointer.
public enum RemappingMouseButton: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left button.
  case left = "Left"
  /// The right button.
  case right = "Right"
  /// The middle button.
  case middle = "Middle"
  /// The back button.
  case back = "Back"
  /// The forward button.
  case forward = "Forward"
}

/// Axis of the pointer or of scrolling.
public enum RemappingPointerAxis: String, Codable, CaseIterable, Hashable, Sendable {
  /// Horizontal.
  case x = "X"
  /// Vertical.
  case y = "Y"
}
