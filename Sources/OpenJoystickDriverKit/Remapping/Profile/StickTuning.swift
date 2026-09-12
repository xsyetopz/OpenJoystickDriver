import Foundation

/// Radial stick calibration. Outer deadzone is the unused rim below full deflection.
public struct RemappingStickTuning: Codable, Equatable, Hashable, Sendable {
  public let innerDeadzone: Double
  public let outerDeadzone: Double
  public let responseExponent: Double
  public let invertX: Bool
  public let invertY: Bool

  public static let `default` = Self()

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

  public func validate() throws {
    guard innerDeadzone.isFinite, outerDeadzone.isFinite,
      (0...0.95).contains(innerDeadzone), (0...0.95).contains(outerDeadzone),
      innerDeadzone + outerDeadzone < 1
    else { throw RemappingStickTuningError.invalidDeadzones }
    guard responseExponent.isFinite, (0.1...10).contains(responseExponent) else {
      throw RemappingStickTuningError.invalidExponent
    }
  }

  private enum CodingKeys: String, CodingKey {
    case innerDeadzone = "inner_deadzone"
    case outerDeadzone = "outer_deadzone"
    case responseExponent = "response_exponent"
    case invertX = "invert_x"
    case invertY = "invert_y"
  }

  public init(from decoder: any Decoder) throws {
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

public enum RemappingStickTuningError: Error, Equatable, Sendable {
  case invalidDeadzones
  case invalidExponent
}
