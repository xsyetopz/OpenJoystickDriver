/// Keeps input held across a lifted foreground gate invisible, per field, until that field changes.
///
/// A field whose input still equals the value it had when the mask was taken shows the value last
/// dispatched instead; once it differs it is revealed for the rest of the mask's life.
struct ForegroundInputMask {
  /// One part of the controller state that is revealed independently of the others.
  private enum Field: Hashable {
    /// One control button.
    case control(Control)
    /// The hat switch.
    case hat
    /// The left stick.
    case leftStick
    /// The right stick.
    case rightStick
    /// The left trigger.
    case leftTrigger
    /// The right trigger.
    case rightTrigger
  }

  /// The input at the time the mask was taken.
  private let hidden: ControllerState
  /// The fields whose input changed since the mask was taken.
  private var revealed: Set<Field> = []

  /// Creates a mask that hides `hidden`.
  init(hiding hidden: ControllerState) { self.hidden = hidden }

  /// `input` with every still-hidden field taken from `shown`.
  mutating func visible(_ input: ControllerState, shown: ControllerState) -> ControllerState {
    var visible = input
    for control in input.pressed.union(hidden.pressed).union(shown.pressed) {
      let isPressed = input.pressed.contains(control)
      if reveals(.control(control), isPressed != hidden.pressed.contains(control)) { continue }
      if shown.pressed.contains(control) {
        visible.pressed.insert(control)
      } else {
        visible.pressed.remove(control)
      }
    }
    if !reveals(.hat, input.hat != hidden.hat) { visible.hat = shown.hat }
    if !reveals(.leftStick, input.leftStick != hidden.leftStick) {
      visible.leftStick = shown.leftStick
    }
    if !reveals(.rightStick, input.rightStick != hidden.rightStick) {
      visible.rightStick = shown.rightStick
    }
    if !reveals(.leftTrigger, input.leftTrigger != hidden.leftTrigger) {
      visible.leftTrigger = shown.leftTrigger
    }
    if !reveals(.rightTrigger, input.rightTrigger != hidden.rightTrigger) {
      visible.rightTrigger = shown.rightTrigger
    }
    return visible
  }

  /// Records `field` as revealed when it `changed`; true once it is revealed.
  private mutating func reveals(_ field: Field, _ changed: Bool) -> Bool {
    if changed { revealed.insert(field) }
    return revealed.contains(field)
  }
}
