import Foundation

enum RemappingTransform {
  static let hysteresisWidth = 0.05

  static func value(_ rawValue: Float, tuning: RemappingAxisTuning) -> Double {
    let clamped = min(max(Double(rawValue), -1), 1)
    let magnitude = abs(clamped)
    guard magnitude > tuning.deadzone else { return 0 }

    let scaled = min(max((magnitude - tuning.deadzone) / (1 - tuning.deadzone), 0), 1)
    let curved: Double
    switch tuning.responseCurve {
    case .linear:
      curved = scaled
    case .easeIn:
      curved = scaled * scaled
    case .easeOut:
      curved = 1 - ((1 - scaled) * (1 - scaled))
    case .smoothStep:
      curved = scaled * scaled * (3 - (2 * scaled))
    }

    let sign = clamped.sign == .minus ? -1.0 : 1.0
    let invertedSign = tuning.inverted ? -sign : sign
    return min(max(curved * tuning.gain * invertedSign, -1), 1)
  }

  static func isDirectionActive(
    value: Double,
    direction: RemappingAxisDirection,
    threshold: Double,
    wasActive: Bool
  ) -> Bool {
    let directionalMagnitude: Double
    switch direction {
    case .negative:
      directionalMagnitude = max(-value, 0)
    case .positive:
      directionalMagnitude = max(value, 0)
    }
    let releaseThreshold = max(0, threshold - Self.hysteresisWidth)
    return wasActive
      ? directionalMagnitude > releaseThreshold
      : directionalMagnitude >= threshold
  }
}
