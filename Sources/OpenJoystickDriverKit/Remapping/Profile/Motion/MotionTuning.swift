import Foundation

/// Angular tuning shared by native motion profile authoring and runtime processing.
public struct RemappingMotionTuning: Codable, Equatable, Hashable, Sendable {
  /// Frame in which gyro motion becomes pitch and yaw rates.
  public let space: RemappingMotionSpace
  /// Multiplier of the pitch rate.
  public let pitchSensitivity: Double
  /// Multiplier of the yaw rate.
  public let yawSensitivity: Double
  /// Whether the pitch rate is negated.
  public let invertPitch: Bool
  /// Whether the yaw rate is negated.
  public let invertYaw: Bool
  /// Time in which smoothing closes half the gap to the input, in milliseconds; 0 turns smoothing
  /// off.
  public let smoothingHalfTimeMs: Double
  /// Angular speed below which motion is cut, in degrees per second.
  public let thresholdDegreesPerSecond: Double
  /// Whether the gyro bias is estimated from steady samples.
  public let automaticBias: Bool
  /// How much of the rotation about gravity ``RemappingMotionSpace/player`` counts as yaw.
  public let yawRelaxation: Double
  /// Gravity share along the controller's Y and Z axes under which
  /// ``RemappingMotionSpace/world`` reduces pitch, from 0 to 1.
  public let sideReductionThreshold: Double
  /// Rate at which the accelerometer pulls the orientation toward gravity; 0 trusts the gyro only.
  public let gravityCorrectionRate: Double
  /// Tilt thresholds that make leaning left or right a binding source, or `nil` for none.
  public let lean: RemappingMotionLean?
  /// Steering axis driven by lean, or `nil` for none.
  public let steering: RemappingMotionSteering?

  /// Tuning with every field at its initializer default.
  public static let `default` = Self()

  /// Creates a motion tuning.
  ///
  /// The initializer does not validate; call ``validate()``.
  public init(
    space: RemappingMotionSpace = .player,
    pitchSensitivity: Double = 1,
    yawSensitivity: Double = 1,
    invertPitch: Bool = false,
    invertYaw: Bool = false,
    smoothingHalfTimeMs: Double = 0,
    thresholdDegreesPerSecond: Double = 0,
    automaticBias: Bool = true,
    yawRelaxation: Double = 1.41,
    sideReductionThreshold: Double = 0.125,
    gravityCorrectionRate: Double = 2,
    lean: RemappingMotionLean? = nil,
    steering: RemappingMotionSteering? = nil
  ) {
    self.space = space
    self.pitchSensitivity = pitchSensitivity
    self.yawSensitivity = yawSensitivity
    self.invertPitch = invertPitch
    self.invertYaw = invertYaw
    self.smoothingHalfTimeMs = smoothingHalfTimeMs
    self.thresholdDegreesPerSecond = thresholdDegreesPerSecond
    self.automaticBias = automaticBias
    self.yawRelaxation = yawRelaxation
    self.sideReductionThreshold = sideReductionThreshold
    self.gravityCorrectionRate = gravityCorrectionRate
    self.lean = lean
    self.steering = steering
  }

  /// Checks every numeric field against its range, then the lean and the steering setting.
  /// - Throws: ``RemappingMotionTuningError/invalidField(_:)`` with the snake_case field name.
  public func validate() throws {
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("pitch_sensitivity", pitchSensitivity, 0...100),
      ("yaw_sensitivity", yawSensitivity, 0...100),
      ("smoothing_half_time_ms", smoothingHalfTimeMs, 0...1000),
      ("threshold_degrees_per_second", thresholdDegreesPerSecond, 0...1000),
      ("yaw_relaxation", yawRelaxation, 0...10),
      ("side_reduction_threshold", sideReductionThreshold, 0...1),
      ("gravity_correction_rate", gravityCorrectionRate, 0...100),
    ]
    for (field, value, range) in fields {
      guard value.isFinite, range.contains(value) else {
        throw RemappingMotionTuningError.invalidField(field)
      }
    }
    try lean?.validate()
    try steering?.validate()
  }

  /// Profile document keys of a motion tuning.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `space`.
    case space
    /// The JSON key of `pitchSensitivity`.
    case pitchSensitivity
    /// The JSON key of `yawSensitivity`.
    case yawSensitivity
    /// The JSON key of `invertPitch`.
    case invertPitch
    /// The JSON key of `invertYaw`.
    case invertYaw
    /// The JSON key of `smoothingHalfTimeMs`.
    case smoothingHalfTimeMs
    /// The JSON key of `thresholdDegreesPerSecond`.
    case thresholdDegreesPerSecond
    /// The JSON key of `automaticBias`.
    case automaticBias
    /// The JSON key of `yawRelaxation`.
    case yawRelaxation
    /// The JSON key of `sideReductionThreshold`.
    case sideReductionThreshold
    /// The JSON key of `gravityCorrectionRate`.
    case gravityCorrectionRate
    /// The JSON key of `lean`.
    case lean
    /// The JSON key of `steering`.
    case steering
  }

  /// Decodes a motion tuning from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      space: try values.decodeIfPresent(RemappingMotionSpace.self, forKey: .space) ?? .player,
      pitchSensitivity: try values.decodeIfPresent(Double.self, forKey: .pitchSensitivity) ?? 1,
      yawSensitivity: try values.decodeIfPresent(Double.self, forKey: .yawSensitivity) ?? 1,
      invertPitch: try values.decodeIfPresent(Bool.self, forKey: .invertPitch) ?? false,
      invertYaw: try values.decodeIfPresent(Bool.self, forKey: .invertYaw) ?? false,
      smoothingHalfTimeMs: try values.decodeIfPresent(Double.self, forKey: .smoothingHalfTimeMs)
        ?? 0,
      thresholdDegreesPerSecond: try values.decodeIfPresent(
        Double.self,
        forKey: .thresholdDegreesPerSecond
      ) ?? 0,
      automaticBias: try values.decodeIfPresent(Bool.self, forKey: .automaticBias) ?? true,
      yawRelaxation: try values.decodeIfPresent(Double.self, forKey: .yawRelaxation) ?? 1.41,
      sideReductionThreshold: try values.decodeIfPresent(
        Double.self,
        forKey: .sideReductionThreshold
      ) ?? 0.125,
      gravityCorrectionRate: try values.decodeIfPresent(Double.self, forKey: .gravityCorrectionRate)
        ?? 2,
      lean: try values.decodeIfPresent(RemappingMotionLean.self, forKey: .lean),
      steering: try values.decodeIfPresent(RemappingMotionSteering.self, forKey: .steering)
    )
    try validate()
  }
}

/// Error for an invalid motion tuning.
public enum RemappingMotionTuningError: Error, Equatable, LocalizedError, Sendable {
  /// A field is outside its valid range.
  case invalidField(String)

  /// Message that names the field that is outside its valid range.
  public var errorDescription: String? {
    switch self {
    case .invalidField(let field): "Motion tuning field '\(field)' is outside its valid range."
    }
  }
}
