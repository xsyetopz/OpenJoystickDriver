/// Coordinate frame for converting calibrated gyro motion into pitch and yaw rates.
public enum RemappingMotionSpace: String, Codable, Sendable, CaseIterable {
  /// Pitch and yaw are the rotations about the controller's own X and Y axes.
  case local = "Local"
  /// Pitch is the rotation about the controller's X axis; yaw combines its Y and Z rotation by
  /// their share along gravity, relaxed by ``RemappingMotionTuning/yawRelaxation``.
  case player = "Player"
  /// Yaw is the rotation about gravity and pitch the rotation about the horizontal axis; pitch is
  /// reduced when the controller lies on its side, per
  /// ``RemappingMotionTuning/sideReductionThreshold``.
  case world = "World"
}
