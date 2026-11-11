/// A three-axis motion vector.
///
/// Each property that stores one declares its units and frame.
public struct ControllerMotionVector: Sendable, Equatable, Codable {
  /// The X component.
  public let x: Double
  /// The Y component.
  public let y: Double
  /// The Z component.
  public let z: Double

  /// Creates a vector from its three components.
  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  /// Whether all three components are finite numbers.
  var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

/// How a motion sample's scale was calibrated.
public enum ControllerMotionCalibrationSource: String, Sendable, Codable {
  /// The nominal scale of the device model, without per-unit factory data.
  case nominalDeviceScale
  /// Factory calibration data read from the device.
  case deviceFactory
  /// Factory calibration data with user offsets applied.
  case factoryWithUserOffsets
}

/// Unit factors shared by motion producers and the remapping consumer.
enum ControllerMotionUnits {
  /// The standard gravity in m/s², the value of `SDL_STANDARD_GRAVITY` in SDL
  /// `include/SDL3/SDL_sensor.h` at SDL `1ce4c5bc`.
  static let standardGravity = 9.80665
  /// The number of radians in one degree.
  static let radiansPerDegree = Double.pi / 180
}
