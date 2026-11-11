import Foundation

/// Axis value shaping and direction detection.
enum RemappingTransform {
  /// Margin below a direction threshold that keeps the direction active.
  static let hysteresisWidth = 0.05

  /// Returns an axis value after dead zone, response curve, gain and inversion, from -1 to 1.
  static func value(_ rawValue: Float, tuning: RemappingAxisTuning) -> Double {
    let clamped = min(max(Double(rawValue), -1), 1)
    let magnitude = abs(clamped)
    guard magnitude > tuning.deadzone else { return 0 }

    let scaled = min(max((magnitude - tuning.deadzone) / (1 - tuning.deadzone), 0), 1)
    let curved = tuning.responseCurve.shaped(scaled)

    let sign = clamped.sign == .minus ? -1.0 : 1.0
    let invertedSign = tuning.inverted ? -sign : sign
    return min(max(curved * tuning.gain * invertedSign, -1), 1)
  }

  /// Whether a direction of a shaped axis value is active.
  ///
  /// A direction becomes active at the threshold and stays active while the magnitude is above the
  /// threshold minus ``hysteresisWidth``.
  static func isDirectionActive(
    value: Double,
    direction: RemappingAxisDirection,
    threshold: Double,
    wasActive: Bool
  ) -> Bool {
    let directionalMagnitude: Double
    switch direction {
    case .negative: directionalMagnitude = max(-value, 0)
    case .positive: directionalMagnitude = max(value, 0)
    }
    let releaseThreshold = max(0, threshold - Self.hysteresisWidth)
    return wasActive ? directionalMagnitude > releaseThreshold : directionalMagnitude >= threshold
  }
}
