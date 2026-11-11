import Foundation

/// The stick deflection, as a fraction of full travel, within which a stick counts as at rest.
private let controllerSleepStickDeadzone: Float = 0.15
/// The trigger value, as a fraction of full travel, within which a trigger counts as at rest.
private let controllerSleepTriggerDeadzone: Float = 0.05

extension ControllerState {
  /// Whether no control is held and every stick and trigger rests within the sleep dead zones.
  var isEffectivelyNeutral: Bool {
    pressed.isEmpty && hat == .neutral && !leftStick.isBeyondSleepDeadzone
      && !rightStick.isBeyondSleepDeadzone && !leftTrigger.isBeyondSleepDeadzone
      && !rightTrigger.isBeyondSleepDeadzone
  }
}

extension StickPosition {
  /// Whether either axis of the stick is beyond the sleep dead zone.
  var isBeyondSleepDeadzone: Bool {
    abs(x.normalized) > controllerSleepStickDeadzone
      || abs(y.normalized) > controllerSleepStickDeadzone
  }
}

extension UnipolarValue {
  /// Whether the trigger value is beyond the sleep dead zone.
  var isBeyondSleepDeadzone: Bool { normalized > controllerSleepTriggerDeadzone }
}
