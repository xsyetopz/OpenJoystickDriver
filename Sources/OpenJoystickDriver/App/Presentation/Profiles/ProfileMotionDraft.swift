import Foundation
import OpenJoystickDriverKit

struct ProfileMotionDraft {
  var space: RemappingMotionSpace
  var pitchSensitivity: Double
  var yawSensitivity: Double
  var invertPitch: Bool
  var invertYaw: Bool
  var smoothingHalfTimeMs: Double
  var thresholdDegreesPerSecond: Double
  var automaticBias: Bool
  var yawRelaxation: Double
  var sideReductionThreshold: Double
  var gravityCorrectionRate: Double
  var leanEnabled: Bool
  var leanThresholdDegrees: Double
  var leanHysteresisDegrees: Double
  var steeringEnabled: Bool
  var steeringOutput: RemappingMotionSteeringOutput
  var steeringDeadzoneDegrees: Double
  var steeringFullScaleDegrees: Double
  var steeringResponseExponent: Double
  var steeringInverted: Bool

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

  var numericText: [String: String] {
    [
      "pitchSensitivity": String(pitchSensitivity),
      "yawSensitivity": String(yawSensitivity),
      "smoothingHalfTimeMs": String(smoothingHalfTimeMs),
      "thresholdDegreesPerSecond": String(thresholdDegreesPerSecond),
      "yawRelaxation": String(yawRelaxation),
      "sideReductionThreshold": String(sideReductionThreshold),
      "gravityCorrectionRate": String(gravityCorrectionRate),
      "leanThresholdDegrees": String(leanThresholdDegrees),
      "leanHysteresisDegrees": String(leanHysteresisDegrees),
      "steeringDeadzoneDegrees": String(steeringDeadzoneDegrees),
      "steeringFullScaleDegrees": String(steeringFullScaleDegrees),
      "steeringResponseExponent": String(steeringResponseExponent)
    ]
  }

  func applyingNumericText(
    _ text: [String: String], decimalSeparator: String = "."
  ) throws -> Self {
    func number(_ field: String) throws -> Double {
      guard let raw = text[field] else {
        throw RemappingMotionTuningError.invalidField(field)
      }
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

  static func numericValue(_ raw: String, decimalSeparator: String = ".") -> Double? {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: decimalSeparator, with: ".")
    guard let value = Double(normalized), value.isFinite else { return nil }
    return value
  }

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
