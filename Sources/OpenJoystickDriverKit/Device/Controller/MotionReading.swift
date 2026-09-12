/// A vector in the controller's canonical right-handed frame: X right, Y up, Z toward the player.
public struct ControllerMotionVector: Sendable, Equatable, Codable {
  public let x: Double
  public let y: Double
  public let z: Double

  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

public enum ControllerMotionCalibrationSource: String, Sendable, Codable {
  case nominalDeviceScale
  case deviceFactory
  case factoryWithUserOffsets
}

/// Physical-unit readings in the GamepadMotion Y-up frame.
/// Runtime bias estimation and fusion are applied later.
/// Nominal scaling is explicit and must not be presented as device factory calibration.
public struct ControllerMotionReading: Sendable, Equatable, Codable {
  public let gyroscopeDegreesPerSecond: ControllerMotionVector
  public let accelerationG: ControllerMotionVector
  public let calibrationSource: ControllerMotionCalibrationSource
  /// Changes when installed calibration coefficients change within a controller session.
  public let calibrationRevision: UInt64

  public init?(
    gyroscopeDegreesPerSecond: ControllerMotionVector,
    accelerationG: ControllerMotionVector,
    calibrationSource: ControllerMotionCalibrationSource,
    calibrationRevision: UInt64 = 0
  ) {
    guard gyroscopeDegreesPerSecond.isFinite, accelerationG.isFinite else { return nil }
    self.gyroscopeDegreesPerSecond = gyroscopeDegreesPerSecond
    self.accelerationG = accelerationG
    self.calibrationSource = calibrationSource
    self.calibrationRevision = calibrationRevision
  }

  private enum CodingKeys: String, CodingKey {
    case gyroscopeDegreesPerSecond, accelerationG, calibrationSource, calibrationRevision
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let reading = try Self(
      gyroscopeDegreesPerSecond: container.decode(
        ControllerMotionVector.self, forKey: .gyroscopeDegreesPerSecond
      ),
      accelerationG: container.decode(ControllerMotionVector.self, forKey: .accelerationG),
      calibrationSource: container.decode(
        ControllerMotionCalibrationSource.self, forKey: .calibrationSource
      ),
      calibrationRevision: container.decodeIfPresent(UInt64.self, forKey: .calibrationRevision) ?? 0
    ) else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: decoder.codingPath, debugDescription: "Motion readings must be finite"
      ))
    }
    self = reading
  }
}
