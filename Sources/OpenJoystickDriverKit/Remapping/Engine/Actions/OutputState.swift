import Foundation

/// Outputs that one controller currently holds.
struct RemappingOutputState {
  /// Virtual gamepad contributions of all owners.
  var gamepad = RemappingGamepadAccumulator()
  /// Destination that each held action drives.
  var heldBindings: [UUID: RemappingDestination] = [:]
  /// Tap-on-release actions whose source is pressed.
  var armedReleaseBindings: Set<UUID> = []
  /// Uptime at which each pulse ends, in nanoseconds.
  var pulseDeadlines: [UUID: UInt64] = [:]
  /// Turbo repeats by action.
  var turbos: [UUID: RemappingTurboOutput] = [:]
  /// Continuous pointer and scroll contributions by owner.
  var continuous: [UUID: RemappingContinuousOutput] = [:]
  /// Long-hold and double-tap trackers by action.
  var activations: [UUID: RemappingActivationTracker] = [:]
}

/// Press history of one action with a long hold or double tap.
struct RemappingActivationTracker {
  /// Uptime of the latest press.
  var pressUptime: UInt64?
  /// Uptime of the latest release.
  var releaseUptime: UInt64?
  /// Taps counted for the latest press: 2 for a double tap, otherwise 1.
  var tapCount: Int = 0
  /// Identifier of the action whose long-hold or double-tap destination is held.
  var firedBindingID: UUID?
  /// Whether the latest press still owes a tap of the default destination.
  var pendingDefault: Bool = false
}
