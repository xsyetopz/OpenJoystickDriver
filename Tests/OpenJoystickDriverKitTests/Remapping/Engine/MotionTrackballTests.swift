import Testing
@testable import OpenJoystickDriverKit

struct MotionTrackballTests {
  @Test func decayAndTravelAreIndependentOfSampleRate() throws {
    func run(interval: Double, count: Int) throws -> (Double, Double) {
      var trackball = RemappingMotionTrackball()
      _ = trackball.process(
        RemappingGyroProjection(pitchDegreesPerSecond: 100, yawDegreesPerSecond: -50),
        deltaTime: 0.01,
        pitchHeld: false,
        yawHeld: false,
        decayHalvingsPerSecond: 1
      )
      var travel = 0.0
      var velocity = 0.0
      for _ in 0..<count {
        let result = trackball.process(
          RemappingGyroProjection(pitchDegreesPerSecond: -500, yawDegreesPerSecond: 500),
          deltaTime: interval,
          pitchHeld: true,
          yawHeld: true,
          decayHalvingsPerSecond: 1
        )
        let step = try #require(result)
        travel += step.pitchDegrees
        velocity = step.velocity.pitchDegreesPerSecond
      }
      return (travel, velocity)
    }
    let slow = try run(interval: 0.1, count: 10)
    let fast = try run(interval: 0.001, count: 1000)
    #expect(abs(slow.0 - fast.0) < 1e-9)
    #expect(abs(slow.1 - 50) < 1e-9)
    #expect(abs(fast.1 - 50) < 1e-9)
  }

  @Test func axesAreIndependentAndResetDropsRetainedVelocity() throws {
    var trackball = RemappingMotionTrackball()
    let first = RemappingGyroProjection(pitchDegreesPerSecond: 100, yawDegreesPerSecond: 50)
    _ = trackball.process(
      first, deltaTime: 0.01, pitchHeld: false, yawHeld: false, decayHalvingsPerSecond: 0
    )
    let next = RemappingGyroProjection(pitchDegreesPerSecond: -100, yawDegreesPerSecond: -50)
    let result = trackball.process(
      next, deltaTime: 0.01, pitchHeld: true, yawHeld: false, decayHalvingsPerSecond: 0
    )
    let step = try #require(result)
    #expect(step.pitchDegrees == 1)
    #expect(step.yawDegrees == -0.5)
    trackball.reset()
    let resetResult = trackball.process(
      next, deltaTime: 0.01, pitchHeld: true, yawHeld: true, decayHalvingsPerSecond: 0
    )
    let reset = try #require(resetResult)
    #expect(reset.pitchDegrees == 0 && reset.yawDegrees == 0)
  }
}
