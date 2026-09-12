import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionFusionTests {
  private let zero = ControllerMotionVector(x: 0, y: 0, z: 0)
  private let up = ControllerMotionVector(x: 0, y: 1, z: 0)

  @Test(arguments: [
    ControllerMotionVector(x: 0, y: 1, z: 0),
    ControllerMotionVector(x: 1, y: 0, z: 0),
    ControllerMotionVector(x: 0, y: -1, z: 0)
  ]) func initializationAlignsGravityIncludingUpsideDown(_ accel: ControllerMotionVector) throws {
    var fusion = RemappingMotionFusion()
    let updated = fusion.update(gyro: zero, acceleration: accel, deltaTime: 0)
    let result = try #require(updated)
    #expect(abs(result.gravityG.x + accel.x) < 1e-9)
    #expect(abs(result.gravityG.y + accel.y) < 1e-9)
    #expect(abs(result.gravityG.z + accel.z) < 1e-9)
    #expect(abs(result.linearAccelerationG.x) < 1e-9)
  }

  @Test func yawIntegrationUsesDegreesAndKeepsUnitOrientation() throws {
    var fusion = RemappingMotionFusion()
    _ = fusion.update(gyro: zero, acceleration: up, deltaTime: 0)
    for _ in 0..<100 {
      _ = fusion.update(
        gyro: ControllerMotionVector(x: 0, y: 90, z: 0), acceleration: up, deltaTime: 0.01
      )
    }
    let updated = fusion.update(gyro: zero, acceleration: up, deltaTime: 0)
    let result = try #require(updated)
    let rotated = result.orientation.rotate(SIMD3(0, 0, 1))
    #expect(abs(rotated.x - 1) < 1e-9)
    #expect(abs(rotated.z) < 1e-9)
    #expect(abs(result.gravityG.y + 1) < 1e-9)
  }

  @Test func gapsAndInvalidReadingsCannotPoisonOrientation() throws {
    var fusion = RemappingMotionFusion()
    let first = fusion.update(gyro: zero, acceleration: up, deltaTime: 0)
    let initial = try #require(first)
    let invalid = fusion.update(
      gyro: ControllerMotionVector(x: .infinity, y: 0, z: 0), acceleration: up, deltaTime: 0.01
    )
    #expect(invalid == nil)
    let gap = fusion.update(gyro: zero, acceleration: up, deltaTime: 1)
    #expect(gap == nil)
    #expect(fusion.orientation == initial.orientation)
    let falling = fusion.update(gyro: zero, acceleration: zero, deltaTime: 0.01)
    let freefall = try #require(falling)
    #expect(freefall.gravityG.y == -1)
    fusion.reset()
    let uninitialized = fusion.update(gyro: zero, acceleration: zero, deltaTime: 0.01)
    #expect(uninitialized == nil)
  }

  @Test func pitchTraceSeparatesGravityFromLinearAcceleration() throws {
    var fusion = RemappingMotionFusion()
    _ = fusion.update(gyro: zero, acceleration: up, deltaTime: 0)
    var last: RemappingFusedMotion?
    for index in 1...100 {
      let angle = Double(index) * .pi / 200
      last = fusion.update(
        gyro: ControllerMotionVector(x: 90, y: 0, z: 0),
        acceleration: ControllerMotionVector(x: 0, y: cos(angle), z: -sin(angle)),
        deltaTime: 0.01
      )
    }
    let result = try #require(last)
    #expect(abs(result.gravityG.z - 1) < 1e-9)
    #expect(abs(result.linearAccelerationG.z) < 1e-9)
    #expect(abs(result.linearAccelerationG.y) < 1e-9)
    // A 2 g pulse is not a valid tilt reference and must not rotate the orientation.
    let pulse = fusion.update(
      gyro: zero, acceleration: ControllerMotionVector(x: 2, y: 0, z: 0), deltaTime: 0.01
    )
    #expect(pulse?.orientation == result.orientation)
    #expect(pulse?.linearAccelerationG.x == 2)
  }
}
