import Foundation

/// Applies radial calibration without making diagonal input faster than cardinal input.
enum RemappingStickTransform {
  static func value(x: Double, y: Double, tuning: RemappingStickTuning) -> SIMD2<Double>? {
    guard x.isFinite, y.isFinite, (try? tuning.validate()) != nil else { return nil }
    let clamped = SIMD2(max(-1, min(1, x)), max(-1, min(1, y)))
    let magnitude = hypot(clamped.x, clamped.y)
    guard magnitude > tuning.innerDeadzone else { return .zero }
    let range = 1 - tuning.outerDeadzone - tuning.innerDeadzone
    let normalized = min(1, (magnitude - tuning.innerDeadzone) / range)
    let scale = pow(normalized, tuning.responseExponent) / magnitude
    return SIMD2(
      clamped.x * scale * (tuning.invertX ? -1 : 1),
      clamped.y * scale * (tuning.invertY ? -1 : 1)
    )
  }
}
