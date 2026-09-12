/// Coordinate frame for converting calibrated gyro motion into pitch and yaw rates.
public enum RemappingMotionSpace: String, Codable, Sendable, CaseIterable {
  case local
  case player
  case world
}
