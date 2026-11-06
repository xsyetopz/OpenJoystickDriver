import Foundation

/// The one trigger-press policy for protocols without a distinct digital trigger signal.
///
/// A driver whose protocol reports a physical digital trigger lists that trigger in the
/// `digitalTriggers` of its capabilities and emits `leftTrigger` or `rightTrigger` in `pressed`
/// from that signal. For any other trigger in `controls`, normalization derives the press from the
/// canonical analog value: it presses at `pressThreshold` and, once pressed, releases only at or
/// below `releaseThreshold`. The values reuse the remapping defaults for an axis acting as a
/// button, applied here to the canonical value with no dead zone. A remapped trigger axis sets the
/// virtual digital trigger by the same rule.
enum TriggerButtonDerivation {
  /// The analog trigger value at which a trigger presses.
  static let pressThreshold = UnipolarValue(
    normalized: Float(RemappingAxisTuning.defaultDigitalActivationThreshold)
  )
  /// The analog trigger value at or below which a pressed trigger releases.
  static let releaseThreshold = UnipolarValue(
    normalized: Float(
      RemappingAxisTuning.defaultDigitalActivationThreshold - RemappingTransform.hysteresisWidth
    )
  )

  /// The trigger sides `capabilities` leaves to derivation: a trigger with no declared digital
  /// signal.
  static func derivedSides(
    of capabilities: ControllerCapabilities
  ) -> [(trigger: KeyPath<ControllerState, UnipolarValue>, button: Control)] {
    [
      (\ControllerState.leftTrigger, Control.leftTrigger),
      (\ControllerState.rightTrigger, Control.rightTrigger),
    ].compactMap { trigger, control in
      capabilities.controls.contains(control) && !capabilities.digitalTriggers.contains(control)
        ? (trigger, control) : nil
    }
  }

  /// `state` with each derived trigger button set from its analog trigger; `previous` is the last
  /// normalized state, whose derived button decides which threshold applies.
  static func applying(
    to state: ControllerState,
    previous: ControllerState,
    capabilities: ControllerCapabilities
  ) -> ControllerState {
    var next = state
    for (trigger, button) in derivedSides(of: capabilities) {
      next.set(
        button,
        pressed: isPressed(state[keyPath: trigger], wasPressed: previous.pressed.contains(button))
      )
    }
    return next
  }

  /// Whether a trigger at `value` reads as pressed, given whether it read as pressed before.
  static func isPressed(_ value: UnipolarValue, wasPressed: Bool) -> Bool {
    wasPressed
      ? value.rawValue > releaseThreshold.rawValue : value.rawValue >= pressThreshold.rawValue
  }
}
