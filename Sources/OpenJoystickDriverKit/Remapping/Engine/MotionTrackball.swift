import Foundation

/// Per-device angular velocity retained while a trackball control is held.
/// Callers reset this state on activation, calibration, profile, and sample-clock discontinuities.
struct RemappingMotionTrackball {
  private var velocity = SIMD2<Double>.zero

  struct Step {
    let velocity: RemappingGyroProjection
    let pitchDegrees: Double
    let yawDegrees: Double
  }

  mutating func reset() { velocity = .zero }

  mutating func process(
    _ input: RemappingGyroProjection,
    deltaTime: Double,
    pitchHeld: Bool,
    yawHeld: Bool,
    decayHalvingsPerSecond: Double
  ) -> Step? {
    guard deltaTime.isFinite, (0...0.1).contains(deltaTime),
      decayHalvingsPerSecond.isFinite, (0...1000).contains(decayHalvingsPerSecond),
      input.pitchDegreesPerSecond.isFinite, input.yawDegreesPerSecond.isFinite,
      max(abs(input.pitchDegreesPerSecond), abs(input.yawDegreesPerSecond)) <= 200_000_000
    else { reset(); return nil }
    guard deltaTime > 0 else { reset(); return nil }
    let rate = decayHalvingsPerSecond * log(2)
    let decay = exp(-rate * deltaTime)
    // expm1 preserves small intervals; the zero-decay limit is constant velocity.
    let integral = rate == 0 ? deltaTime : -expm1(-rate * deltaTime) / rate
    let inputVelocity = SIMD2(input.pitchDegreesPerSecond, input.yawDegreesPerSecond)
    var degrees = SIMD2<Double>.zero
    for axis in 0..<2 {
      let held = axis == 0 ? pitchHeld : yawHeld
      if held {
        degrees[axis] = velocity[axis] * integral
        velocity[axis] *= decay
      } else {
        velocity[axis] = inputVelocity[axis]
        degrees[axis] = velocity[axis] * deltaTime
      }
    }
    return Step(
      velocity: RemappingGyroProjection(
        pitchDegreesPerSecond: velocity.x, yawDegreesPerSecond: velocity.y
      ),
      pitchDegrees: degrees.x,
      yawDegrees: degrees.y
    )
  }
}
