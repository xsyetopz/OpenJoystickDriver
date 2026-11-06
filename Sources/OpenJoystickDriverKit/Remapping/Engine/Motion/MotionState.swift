import Foundation

/// Motion processing and motion-driven output state of one controller.
struct RemappingMotionState {
  /// Sample processor with the controller's clock, bias and orientation.
  var motion = RemappingMotionProcessor()
  /// Owner identity of the gyro stick's contribution to the virtual gamepad.
  let gyroBindingID = UUID()
  /// Owner identity of the tilt steering contribution to the virtual gamepad.
  let motionSteeringBindingID = UUID()
  /// Uptime after which the gyro stick output expires, or `nil` when none is set.
  var gyroDeadline: UInt64?
  /// Uptime after which tilt steering and lean output expire, or `nil` when none is set.
  var motionStickDeadline: UInt64?
  /// Whether a toggle gyro activation is switched on.
  var gyroToggleActive = false
  /// Whether the gyro output waits for the first processed sample before it produces output.
  var gyroAwaitingBaseline = true
  /// Trackball velocity of the gyro output.
  var gyroTrackball = RemappingMotionTrackball()
  /// Lean directions that are active.
  var activeMotionLeans: Set<RemappingMotionLeanDirection> = []
}
