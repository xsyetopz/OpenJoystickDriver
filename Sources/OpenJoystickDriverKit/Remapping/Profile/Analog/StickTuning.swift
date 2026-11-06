import Foundation

/// Radial stick calibration.
///
/// Outer deadzone is the unused rim below full deflection.
public struct RemappingStickTuning: Codable, Equatable, Hashable, Sendable {
  /// Deflection radius below which the stick reads as centered.
  public let innerDeadzone: Double
  /// Deflection radius, measured from full deflection, above which the stick reads as full.
  public let outerDeadzone: Double
  /// Exponent of the response curve; 1 is linear.
  public let responseExponent: Double
  /// Whether horizontal output is negated.
  public let invertX: Bool
  /// Whether vertical output is negated.
  public let invertY: Bool

  /// Calibration with a 0.1 inner deadzone, no outer deadzone, a linear response and no inversion.
  public static let `default` = Self()

  /// Creates a stick calibration.
  ///
  /// The initializer does not validate; call ``validate()``.
  public init(
    innerDeadzone: Double = 0.1,
    outerDeadzone: Double = 0,
    responseExponent: Double = 1,
    invertX: Bool = false,
    invertY: Bool = false
  ) {
    self.innerDeadzone = innerDeadzone
    self.outerDeadzone = outerDeadzone
    self.responseExponent = responseExponent
    self.invertX = invertX
    self.invertY = invertY
  }

  /// Checks that the deadzones and the exponent are usable.
  ///
  /// Both deadzones are finite and within 0 to 0.95 and sum to less than 1, and the exponent is
  /// finite and within 0.1 to 10.
  /// - Throws: ``RemappingStickTuningError/invalidDeadzones`` or
  ///   ``RemappingStickTuningError/invalidExponent``.
  public func validate() throws {
    guard innerDeadzone.isFinite, outerDeadzone.isFinite, (0...0.95).contains(innerDeadzone),
      (0...0.95).contains(outerDeadzone), innerDeadzone + outerDeadzone < 1
    else { throw RemappingStickTuningError.invalidDeadzones }
    guard responseExponent.isFinite, (0.1...10).contains(responseExponent) else {
      throw RemappingStickTuningError.invalidExponent
    }
  }

  /// Profile document keys of a stick calibration.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `innerDeadzone`.
    case innerDeadzone
    /// The JSON key of `outerDeadzone`.
    case outerDeadzone
    /// The JSON key of `responseExponent`.
    case responseExponent
    /// The JSON key of `invertX`.
    case invertX
    /// The JSON key of `invertY`.
    case invertY
  }

  /// Decodes a stick calibration from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      innerDeadzone: try values.decodeIfPresent(Double.self, forKey: .innerDeadzone) ?? 0.1,
      outerDeadzone: try values.decodeIfPresent(Double.self, forKey: .outerDeadzone) ?? 0,
      responseExponent: try values.decodeIfPresent(Double.self, forKey: .responseExponent) ?? 1,
      invertX: try values.decodeIfPresent(Bool.self, forKey: .invertX) ?? false,
      invertY: try values.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
    )
    try validate()
  }
}

/// Error for an invalid stick calibration.
public enum RemappingStickTuningError: Error, Equatable, Sendable {
  /// The deadzones are not finite, are out of range or leave no travel.
  case invalidDeadzones
  /// The response exponent is not finite or is out of range.
  case invalidExponent
}
