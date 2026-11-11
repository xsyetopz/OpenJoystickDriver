import OpenJoystickDriverKit

extension ControllerState {
  /// Whether a button, the hat, a stick or a trigger is away from its rest value.
  ///
  /// The pointer, the touch frames and the connection are not controls the Input Test shows as
  /// pressed.
  var hasControlOffRest: Bool {
    !pressed.isEmpty || hat != .neutral || leftStick != .center || rightStick != .center
      || leftTrigger != .min || rightTrigger != .min
  }
}
