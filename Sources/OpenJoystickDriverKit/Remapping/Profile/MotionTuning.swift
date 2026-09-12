import Foundation

/// Angular tuning shared by native motion profile authoring and runtime processing.
public struct RemappingMotionTuning: Codable, Equatable, Hashable, Sendable {
  public let space: RemappingMotionSpace
  public let pitchSensitivity: Double
  public let yawSensitivity: Double
  public let invertPitch: Bool
  public let invertYaw: Bool
  public let smoothingHalfTimeMs: Double
  public let thresholdDegreesPerSecond: Double
  public let automaticBias: Bool
  public let yawRelaxation: Double
  public let sideReductionThreshold: Double
  public let gravityCorrectionRate: Double
  public let lean: RemappingMotionLean?
  public let steering: RemappingMotionSteering?

  public static let `default` = Self()

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

  public func validate() throws {
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("pitch_sensitivity", pitchSensitivity, 0...100),
      ("yaw_sensitivity", yawSensitivity, 0...100),
      ("smoothing_half_time_ms", smoothingHalfTimeMs, 0...1000),
      ("threshold_degrees_per_second", thresholdDegreesPerSecond, 0...1000),
      ("yaw_relaxation", yawRelaxation, 0...10),
      ("side_reduction_threshold", sideReductionThreshold, 0...1),
      ("gravity_correction_rate", gravityCorrectionRate, 0...100)
    ]
    for (field, value, range) in fields {
      guard value.isFinite, range.contains(value) else {
        throw RemappingMotionTuningError.invalidField(field)
      }
    }
    try lean?.validate()
    try steering?.validate()
  }

  private enum CodingKeys: String, CodingKey {
    case space
    case pitchSensitivity = "pitch_sensitivity"
    case yawSensitivity = "yaw_sensitivity"
    case invertPitch = "invert_pitch"
    case invertYaw = "invert_yaw"
    case smoothingHalfTimeMs = "smoothing_half_time_ms"
    case thresholdDegreesPerSecond = "threshold_degrees_per_second"
    case automaticBias = "automatic_bias"
    case yawRelaxation = "yaw_relaxation"
    case sideReductionThreshold = "side_reduction_threshold"
    case gravityCorrectionRate = "gravity_correction_rate"
    case lean
    case steering
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      space: try values.decodeIfPresent(RemappingMotionSpace.self, forKey: .space) ?? .player,
      pitchSensitivity: try values.decodeIfPresent(Double.self, forKey: .pitchSensitivity) ?? 1,
      yawSensitivity: try values.decodeIfPresent(Double.self, forKey: .yawSensitivity) ?? 1,
      invertPitch: try values.decodeIfPresent(Bool.self, forKey: .invertPitch) ?? false,
      invertYaw: try values.decodeIfPresent(Bool.self, forKey: .invertYaw) ?? false,
      smoothingHalfTimeMs: try values.decodeIfPresent(
        Double.self, forKey: .smoothingHalfTimeMs
      ) ?? 0,
      thresholdDegreesPerSecond: try values.decodeIfPresent(
        Double.self, forKey: .thresholdDegreesPerSecond
      ) ?? 0,
      automaticBias: try values.decodeIfPresent(Bool.self, forKey: .automaticBias) ?? true,
      yawRelaxation: try values.decodeIfPresent(Double.self, forKey: .yawRelaxation) ?? 1.41,
      sideReductionThreshold: try values.decodeIfPresent(
        Double.self, forKey: .sideReductionThreshold
      ) ?? 0.125,
      gravityCorrectionRate: try values.decodeIfPresent(Double.self, forKey: .gravityCorrectionRate)
        ?? 2,
      lean: try values.decodeIfPresent(RemappingMotionLean.self, forKey: .lean),
      steering: try values.decodeIfPresent(RemappingMotionSteering.self, forKey: .steering)
    )
    try validate()
  }
}

public enum RemappingMotionTuningError: Error, Equatable, LocalizedError, Sendable {
  case invalidField(String)

  public var errorDescription: String? {
    switch self {
    case .invalidField(let field): "Motion tuning field '\(field)' is outside its valid range."
    }
  }
}
