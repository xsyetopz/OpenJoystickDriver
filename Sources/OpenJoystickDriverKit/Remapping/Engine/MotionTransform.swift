import Foundation

struct RemappingMotionTransform {
  private var smoothed: SIMD2<Double>?
  private var previousTuning: RemappingMotionTuning?

  mutating func apply(
    _ projection: RemappingGyroProjection, deltaTime: Double, tuning: RemappingMotionTuning
  ) -> RemappingGyroProjection? {
    guard (try? tuning.validate()) != nil, deltaTime.isFinite, (0...0.1).contains(deltaTime),
      projection.pitchDegreesPerSecond.isFinite, projection.yawDegreesPerSecond.isFinite,
      max(abs(projection.pitchDegreesPerSecond), abs(projection.yawDegreesPerSecond)) <= 2_000_000
    else { smoothed = nil; return nil }
    if previousTuning != tuning || deltaTime == 0 { smoothed = nil }
    previousTuning = tuning
    var value = SIMD2(projection.pitchDegreesPerSecond, projection.yawDegreesPerSecond)
    let magnitude = sqrt(value.x * value.x + value.y * value.y)
    if magnitude > 0 {
      value *= max(0, magnitude - tuning.thresholdDegreesPerSecond) / magnitude
    }
    if let smoothed, tuning.smoothingHalfTimeMs > 0 {
      let alpha = 1 - exp2(-deltaTime * 1000 / tuning.smoothingHalfTimeMs)
      value = smoothed + (value - smoothed) * alpha
    }
    smoothed = value
    return RemappingGyroProjection(
      pitchDegreesPerSecond: value.x * tuning.pitchSensitivity * (tuning.invertPitch ? -1 : 1),
      yawDegreesPerSecond: value.y * tuning.yawSensitivity * (tuning.invertYaw ? -1 : 1)
    )
  }
}
