import Foundation

/// Angular velocity of one controller, kept while a trackball control is held.
///
/// Callers reset it on activation, calibration, profile changes and sample-clock discontinuities.
struct RemappingMotionTrackball {
  /// Held pitch and yaw velocity in degrees per second.
  private var velocity = SIMD2<Double>.zero

  /// Rotation of one trackball step.
  struct Step {
    /// Velocity after the step.
    let velocity: RemappingGyroProjection
    /// Pitch rotation over the step, in degrees.
    let pitchDegrees: Double
    /// Yaw rotation over the step, in degrees.
    let yawDegrees: Double
  }

  /// Clears the held velocity.
  mutating func reset() { velocity = .zero }

  /// Advances the trackball by a time step and returns the rotation of the step.
  ///
  /// A held axis keeps its velocity and decays it exponentially, halving it
  /// `decayHalvingsPerSecond` times each second. An axis that is not held takes the input velocity.
  /// Invalid input, or a time step of zero, resets the trackball and returns `nil`.
  mutating func process(
    _ input: RemappingGyroProjection,
    deltaTime: Double,
    pitchHeld: Bool,
    yawHeld: Bool,
    decayHalvingsPerSecond: Double
  ) -> Step? {
    guard deltaTime.isFinite, (0...0.1).contains(deltaTime), decayHalvingsPerSecond.isFinite,
      (0...1000).contains(decayHalvingsPerSecond), input.pitchDegreesPerSecond.isFinite,
      input.yawDegreesPerSecond.isFinite,
      max(abs(input.pitchDegreesPerSecond), abs(input.yawDegreesPerSecond)) <= 200_000_000
    else {
      reset()
      return nil
    }
    guard deltaTime > 0 else {
      reset()
      return nil
    }
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
        pitchDegreesPerSecond: velocity.x,
        yawDegreesPerSecond: velocity.y
      ),
      pitchDegrees: degrees.x,
      yawDegrees: degrees.y
    )
  }
}
