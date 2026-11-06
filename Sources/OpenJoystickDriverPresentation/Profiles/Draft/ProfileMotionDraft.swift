import Foundation
import OpenJoystickDriverKit

/// The motion tuning as the motion sheet edits it.
struct ProfileMotionDraft {
  /// The space in which the tuning measures motion.
  var space: RemappingMotionSpace
  /// The pitch sensitivity.
  var pitchSensitivity: Double
  /// The yaw sensitivity.
  var yawSensitivity: Double
  /// Whether pitch is inverted.
  var invertPitch: Bool
  /// Whether yaw is inverted.
  var invertYaw: Bool
  /// The smoothing half time in milliseconds.
  var smoothingHalfTimeMs: Double
  /// The threshold in degrees per second.
  var thresholdDegreesPerSecond: Double
  /// Whether the bias is found automatically.
  var automaticBias: Bool
  /// The yaw relaxation.
  var yawRelaxation: Double
  /// The side reduction threshold.
  var sideReductionThreshold: Double
  /// The gravity correction rate.
  var gravityCorrectionRate: Double
  /// Whether the lean source is on.
  var leanEnabled: Bool
  /// The lean threshold in degrees; 15 until the profile sets lean.
  var leanThresholdDegrees: Double
  /// The lean hysteresis in degrees; 2 until the profile sets lean.
  var leanHysteresisDegrees: Double
  /// Whether steering is on.
  var steeringEnabled: Bool
  /// The stick that steering moves.
  var steeringOutput: RemappingMotionSteeringOutput
  /// The steering dead zone in degrees; 5 until the profile sets steering.
  var steeringDeadzoneDegrees: Double
  /// The degrees at which steering reaches full scale; 45 until the profile sets steering.
  var steeringFullScaleDegrees: Double
  /// The steering response exponent; 1 until the profile sets steering.
  var steeringResponseExponent: Double
  /// Whether steering is inverted.
  var steeringInverted: Bool

  /// Creates the draft from the profile's motion tuning.
  init(_ tuning: RemappingMotionTuning) {
    space = tuning.space
    pitchSensitivity = tuning.pitchSensitivity
    yawSensitivity = tuning.yawSensitivity
    invertPitch = tuning.invertPitch
    invertYaw = tuning.invertYaw
    smoothingHalfTimeMs = tuning.smoothingHalfTimeMs
    thresholdDegreesPerSecond = tuning.thresholdDegreesPerSecond
    automaticBias = tuning.automaticBias
    yawRelaxation = tuning.yawRelaxation
    sideReductionThreshold = tuning.sideReductionThreshold
    gravityCorrectionRate = tuning.gravityCorrectionRate
    leanEnabled = tuning.lean != nil
    leanThresholdDegrees = tuning.lean?.thresholdDegrees ?? 15
    leanHysteresisDegrees = tuning.lean?.hysteresisDegrees ?? 2
    steeringEnabled = tuning.steering != nil
    steeringOutput = tuning.steering?.output ?? .leftStickX
    steeringDeadzoneDegrees = tuning.steering?.deadzoneDegrees ?? 5
    steeringFullScaleDegrees = tuning.steering?.fullScaleDegrees ?? 45
    steeringResponseExponent = tuning.steering?.responseExponent ?? 1
    steeringInverted = tuning.steering?.inverted ?? false
  }

  /// The text of each number field by its key, as the sliders' text fields start.
  var numericText: [String: String] {
    [
      "pitchSensitivity": String(pitchSensitivity), "yawSensitivity": String(yawSensitivity),
      "smoothingHalfTimeMs": String(smoothingHalfTimeMs),
      "thresholdDegreesPerSecond": String(thresholdDegreesPerSecond),
      "yawRelaxation": String(yawRelaxation),
      "sideReductionThreshold": String(sideReductionThreshold),
      "gravityCorrectionRate": String(gravityCorrectionRate),
      "leanThresholdDegrees": String(leanThresholdDegrees),
      "leanHysteresisDegrees": String(leanHysteresisDegrees),
      "steeringDeadzoneDegrees": String(steeringDeadzoneDegrees),
      "steeringFullScaleDegrees": String(steeringFullScaleDegrees),
      "steeringResponseExponent": String(steeringResponseExponent),
    ]
  }

  /// Returns the draft with the numbers from `text`, after validating the tuning.
  ///
  /// - Parameters:
  ///   - text: The text of each number field by its key.
  ///   - decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The draft with the numbers from `text`, after validating the tuning.
  /// - Throws: ``RemappingMotionTuningError`` when a field is missing or not a number, and the
  ///   error of the tuning's validation when its values are out of range.
  func applyingNumericText(_ text: [String: String], decimalSeparator: String = ".") throws -> Self
  {
    func number(_ field: String) throws -> Double {
      guard let raw = text[field] else { throw RemappingMotionTuningError.invalidField(field) }
      guard let value = Self.numericValue(raw, decimalSeparator: decimalSeparator) else {
        throw RemappingMotionTuningError.invalidField(field)
      }
      return value
    }
    var result = self
    result.pitchSensitivity = try number("pitchSensitivity")
    result.yawSensitivity = try number("yawSensitivity")
    result.smoothingHalfTimeMs = try number("smoothingHalfTimeMs")
    result.thresholdDegreesPerSecond = try number("thresholdDegreesPerSecond")
    result.yawRelaxation = try number("yawRelaxation")
    result.sideReductionThreshold = try number("sideReductionThreshold")
    result.gravityCorrectionRate = try number("gravityCorrectionRate")
    result.leanThresholdDegrees = try number("leanThresholdDegrees")
    result.leanHysteresisDegrees = try number("leanHysteresisDegrees")
    result.steeringDeadzoneDegrees = try number("steeringDeadzoneDegrees")
    result.steeringFullScaleDegrees = try number("steeringFullScaleDegrees")
    result.steeringResponseExponent = try number("steeringResponseExponent")
    _ = try result.validatedTuning()
    return result
  }

  /// Returns the number in `raw`, or nil when it is not a finite number.
  ///
  /// - Parameters:
  ///   - raw: The text, which may hold spaces around the number.
  ///   - decimalSeparator: The separator that is read as the decimal point.
  /// - Returns: The number in `raw`, or nil when it is not a finite number.
  static func numericValue(_ raw: String, decimalSeparator: String = ".") -> Double? {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
      of: decimalSeparator,
      with: "."
    )
    guard let value = Double(normalized), value.isFinite else { return nil }
    return value
  }

  /// Returns the motion tuning that the draft describes.
  ///
  /// - Throws: The error of the tuning's validation when its values are out of range.
  func validatedTuning() throws -> RemappingMotionTuning {
    let tuning = RemappingMotionTuning(
      space: space,
      pitchSensitivity: pitchSensitivity,
      yawSensitivity: yawSensitivity,
      invertPitch: invertPitch,
      invertYaw: invertYaw,
      smoothingHalfTimeMs: smoothingHalfTimeMs,
      thresholdDegreesPerSecond: thresholdDegreesPerSecond,
      automaticBias: automaticBias,
      yawRelaxation: yawRelaxation,
      sideReductionThreshold: sideReductionThreshold,
      gravityCorrectionRate: gravityCorrectionRate,
      lean: leanEnabled
        ? RemappingMotionLean(
          thresholdDegrees: leanThresholdDegrees,
          hysteresisDegrees: leanHysteresisDegrees
        ) : nil,
      steering: steeringEnabled
        ? RemappingMotionSteering(
          output: steeringOutput,
          deadzoneDegrees: steeringDeadzoneDegrees,
          fullScaleDegrees: steeringFullScaleDegrees,
          responseExponent: steeringResponseExponent,
          inverted: steeringInverted
        ) : nil
    )
    try tuning.validate()
    return tuning
  }
}
