import Foundation

/// Side to which the controller leans.
public enum RemappingMotionLeanDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// Leaning left.
  case left = "Left"
  /// Leaning right.
  case right = "Right"
}

/// Tilt thresholds that turn leaning the controller into a left or right binding source.
public struct RemappingMotionLean: Codable, Equatable, Hashable, Sendable {
  /// Tilt angle at which a lean becomes active, in degrees.
  public let thresholdDegrees: Double
  /// Margin below ``thresholdDegrees`` within which an active lean stays active, in degrees.
  public let hysteresisDegrees: Double

  /// Creates a lean setting.
  public init(thresholdDegrees: Double = 15, hysteresisDegrees: Double = 2) {
    self.thresholdDegrees = thresholdDegrees
    self.hysteresisDegrees = hysteresisDegrees
  }

  /// Checks that the threshold is within 1 to 89 degrees, the hysteresis within 0 to 30 degrees and
  /// below the threshold.
  /// - Throws: ``RemappingMotionTuningError/invalidField(_:)`` with `lean`.
  public func validate() throws {
    guard thresholdDegrees.isFinite, (1...89).contains(thresholdDegrees),
      hysteresisDegrees.isFinite, (0...30).contains(hysteresisDegrees),
      hysteresisDegrees < thresholdDegrees
    else { throw RemappingMotionTuningError.invalidField("lean") }
  }

  /// Profile document keys of a lean setting.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `thresholdDegrees`.
    case thresholdDegrees
    /// The JSON key of `hysteresisDegrees`.
    case hysteresisDegrees
  }

  /// Decodes a lean setting from a profile document, which must give both fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    thresholdDegrees = try values.decode(Double.self, forKey: .thresholdDegrees)
    hysteresisDegrees = try values.decode(Double.self, forKey: .hysteresisDegrees)
  }
}

/// Virtual gamepad axis that motion steering drives.
public enum RemappingMotionSteeringOutput: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left stick horizontal axis of the virtual gamepad.
  case leftStickX = "LeftStickX"
  /// The right stick horizontal axis of the virtual gamepad.
  case rightStickX = "RightStickX"

  /// Virtual gamepad axis that carries the steering value.
  var axis: RemappingAxis {
    switch self {
    case .leftStickX: .leftStickX
    case .rightStickX: .rightStickX
    }
  }
}

/// Maps gravity-derived controller lean to a virtual steering axis.
public struct RemappingMotionSteering: Codable, Equatable, Hashable, Sendable {
  /// Virtual gamepad axis that steering drives.
  public let output: RemappingMotionSteeringOutput
  /// Lean angle below which the axis reads as centered, in degrees.
  public let deadzoneDegrees: Double
  /// Lean angle that gives full deflection, in degrees.
  public let fullScaleDegrees: Double
  /// Exponent of the response curve; 1 is linear.
  public let responseExponent: Double
  /// Whether the axis value is negated.
  public let inverted: Bool

  /// Creates a steering setting.
  public init(
    output: RemappingMotionSteeringOutput = .leftStickX,
    deadzoneDegrees: Double = 5,
    fullScaleDegrees: Double = 45,
    responseExponent: Double = 1,
    inverted: Bool = false
  ) {
    self.output = output
    self.deadzoneDegrees = deadzoneDegrees
    self.fullScaleDegrees = fullScaleDegrees
    self.responseExponent = responseExponent
    self.inverted = inverted
  }

  /// Checks that the dead zone is within 0 to 89 degrees and below the full-scale angle, which is
  /// within 1 to 90 degrees, and that the exponent is within 0.1 to 10.
  /// - Throws: ``RemappingMotionTuningError/invalidField(_:)`` with `steering`.
  public func validate() throws {
    guard deadzoneDegrees.isFinite, (0...89).contains(deadzoneDegrees), fullScaleDegrees.isFinite,
      (1...90).contains(fullScaleDegrees), deadzoneDegrees < fullScaleDegrees,
      responseExponent.isFinite, (0.1...10).contains(responseExponent)
    else { throw RemappingMotionTuningError.invalidField("steering") }
  }

  /// Profile document keys of a steering setting.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `output`.
    case output
    /// The JSON key of `deadzoneDegrees`.
    case deadzoneDegrees
    /// The JSON key of `fullScaleDegrees`.
    case fullScaleDegrees
    /// The JSON key of `responseExponent`.
    case responseExponent
    /// The JSON key of `inverted`.
    case inverted
  }

  /// Decodes a steering setting from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    output = try values.decode(RemappingMotionSteeringOutput.self, forKey: .output)
    deadzoneDegrees = try values.decode(Double.self, forKey: .deadzoneDegrees)
    fullScaleDegrees = try values.decode(Double.self, forKey: .fullScaleDegrees)
    responseExponent = try values.decode(Double.self, forKey: .responseExponent)
    inverted = try values.decode(Bool.self, forKey: .inverted)
  }
}
