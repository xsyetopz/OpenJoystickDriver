import Testing

@testable import OpenJoystickDriverKit

struct MotionTransformTests {
  @Test func radialThresholdPrecedesIndependentSensitivityAndInversion() {
    var transform = RemappingMotionTransform()
    let result = transform.apply(
      RemappingGyroProjection(pitchDegreesPerSecond: 3, yawDegreesPerSecond: 4),
      deltaTime: 0.01,
      tuning: RemappingMotionTuning(
        pitchSensitivity: 2, yawSensitivity: 3, invertYaw: true, thresholdDegreesPerSecond: 1
      )
    )
    #expect(abs((result?.pitchDegreesPerSecond ?? 0) - 4.8) < 1e-9)
    #expect(abs((result?.yawDegreesPerSecond ?? 0) + 9.6) < 1e-9)
  }

  @Test func smoothingUsesElapsedTimeAndConfigurationChangeClearsHistory() {
    let tuning = RemappingMotionTuning(smoothingHalfTimeMs: 100)
    var first = RemappingMotionTransform()
    var second = RemappingMotionTransform()
    let zero = RemappingGyroProjection(pitchDegreesPerSecond: 0, yawDegreesPerSecond: 0)
    let step = RemappingGyroProjection(pitchDegreesPerSecond: 10, yawDegreesPerSecond: 0)
    _ = first.apply(zero, deltaTime: 0, tuning: tuning)
    _ = second.apply(zero, deltaTime: 0, tuning: tuning)
    let single = first.apply(step, deltaTime: 0.1, tuning: tuning)
    var multiple: RemappingGyroProjection?
    for _ in 0..<10 { multiple = second.apply(step, deltaTime: 0.01, tuning: tuning) }
    #expect(abs((single?.pitchDegreesPerSecond ?? 0) - 5) < 1e-9)
    #expect(abs((multiple?.pitchDegreesPerSecond ?? 0) - 5) < 1e-9)
    let changed = second.apply(step, deltaTime: 0.01, tuning: .default)
    #expect(changed?.pitchDegreesPerSecond == 10)
  }
}
