import Foundation

/// Shape of the curve that maps an axis deflection to its output.
public enum RemappingResponseCurve: String, Codable, CaseIterable, Hashable, Sendable {
  /// Output equals the deflection.
  case linear = "Linear"
  /// Output grows slowly at first: the deflection squared.
  case easeIn = "EaseIn"
  /// Output grows quickly at first: the mirror of ``easeIn``.
  case easeOut = "EaseOut"
  /// Output eases in and out along a smooth S curve.
  case smoothStep = "SmoothStep"

  /// Returns the curve output for a deflection from 0 to 1.
  func shaped(_ value: Double) -> Double {
    switch self {
    case .linear: value
    case .easeIn: value * value
    case .easeOut: 1 - ((1 - value) * (1 - value))
    case .smoothStep: value * value * (3 - (2 * value))
    }
  }
}

/// Axis processing applied before a binding reaches its destination.
public struct RemappingAxisTuning: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``deadzone``.
  public static let deadzoneRange = 0.0...0.95
  /// Allowed range of ``gain``.
  public static let gainRange = 0.1...10.0
  /// Allowed range of ``digitalActivationThreshold``.
  public static let digitalActivationThresholdRange = 0.01...1.0
  /// ``deadzone`` used when none is given.
  public static let defaultDeadzone = 0.1
  /// ``gain`` used when none is given.
  public static let defaultGain = 1.0
  /// ``digitalActivationThreshold`` used when none is given.
  public static let defaultDigitalActivationThreshold = 0.5

  /// Deflection below which the axis reads as centered; the range above it is rescaled to 0 to 1.
  public let deadzone: Double
  /// Multiplier applied after the response curve.
  public let gain: Double
  /// Whether the output is negated.
  public let inverted: Bool
  /// Curve applied to the rescaled deflection.
  public let responseCurve: RemappingResponseCurve
  /// Tuned deflection at which an axis direction counts as pressed when it is a digital source.
  public let digitalActivationThreshold: Double

  /// Creates an axis tuning.
  public init(
    deadzone: Double = Self.defaultDeadzone,
    gain: Double = Self.defaultGain,
    inverted: Bool = false,
    responseCurve: RemappingResponseCurve = .linear,
    digitalActivationThreshold: Double = Self.defaultDigitalActivationThreshold
  ) {
    self.deadzone = deadzone
    self.gain = gain
    self.inverted = inverted
    self.responseCurve = responseCurve
    self.digitalActivationThreshold = digitalActivationThreshold
  }

  /// Tuning with the default dead zone, gain, a linear curve and no inversion.
  public static let `default` = Self()

  /// Profile document keys of an axis tuning.
  enum CodingKeys: String, CodingKey, CaseIterable {
    case deadzone
    case gain
    case inverted
    case responseCurve
    case digitalActivationThreshold
  }

  /// Decodes an axis tuning from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    deadzone = try values.decode(Double.self, forKey: .deadzone)
    gain = try values.decode(Double.self, forKey: .gain)
    inverted = try values.decode(Bool.self, forKey: .inverted)
    responseCurve = try values.decode(RemappingResponseCurve.self, forKey: .responseCurve)
    digitalActivationThreshold = try values.decode(Double.self, forKey: .digitalActivationThreshold)
  }
}

/// Repeats a button output while its source is held.
public struct RemappingTurbo: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``repeatRateHz``.
  public static let repeatRateHzRange = 1.0...60.0
  /// Allowed range of ``dutyCycle``.
  public static let dutyCycleRange = 0.05...0.95
  /// Allowed range of ``initialDelayMs``.
  public static let initialDelayMsRange = 0.0...2500.0
  /// Allowed range of ``maxRepeats``.
  public static let maxRepeatsRange = 1...500

  /// Presses per second.
  public let repeatRateHz: Double
  /// Fraction of each repeat period that the output is down.
  public let dutyCycle: Double
  /// Time from the first press to the first repeat in milliseconds; 0 when omitted.
  public let initialDelayMs: Double
  /// Repeats after the first press until the source is released; `nil` repeats while held.
  public let maxRepeats: Int?

  /// Creates a turbo setting.
  public init(
    repeatRateHz: Double,
    dutyCycle: Double,
    initialDelayMs: Double = 0,
    maxRepeats: Int? = nil
  ) {
    self.repeatRateHz = repeatRateHz
    self.dutyCycle = dutyCycle
    self.initialDelayMs = initialDelayMs
    self.maxRepeats = maxRepeats
  }

  /// Profile document keys of a turbo setting.
  enum CodingKeys: String, CodingKey, CaseIterable {
    case repeatRateHz
    case dutyCycle
    case initialDelayMs
    case maxRepeats
  }

  /// Decodes a turbo setting from a profile document; the rate and duty cycle are required.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    repeatRateHz = try values.decode(Double.self, forKey: .repeatRateHz)
    dutyCycle = try values.decode(Double.self, forKey: .dutyCycle)
    initialDelayMs = try values.decodeIfPresent(Double.self, forKey: .initialDelayMs) ?? 0
    maxRepeats = try values.decodeIfPresent(Int.self, forKey: .maxRepeats)
  }

  /// Encodes a turbo setting and leaves out a zero delay and an absent cap.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(repeatRateHz, forKey: .repeatRateHz)
    try values.encode(dutyCycle, forKey: .dutyCycle)
    if initialDelayMs != 0 { try values.encode(initialDelayMs, forKey: .initialDelayMs) }
    try values.encodeIfPresent(maxRepeats, forKey: .maxRepeats)
  }
}
