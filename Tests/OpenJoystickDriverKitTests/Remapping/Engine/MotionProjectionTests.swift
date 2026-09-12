import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionProjectionTests {
  @Test func flatPosePreservesPitchAndYawInEverySpace() throws {
    for space in RemappingMotionSpace.allCases {
      let result = try #require(RemappingMotionProjection.project(
        ControllerMotionVector(x: 3, y: 4, z: 0),
        gravity: ControllerMotionVector(x: 0, y: -1, z: 0),
        space: space
      ))
      #expect(result == RemappingGyroProjection(pitchDegreesPerSecond: 3, yawDegreesPerSecond: 4))
    }
  }

  @Test func sidewaysPoseDistinguishesAllThreeSpaces() throws {
    let gyro = ControllerMotionVector(x: 3, y: 4, z: 0)
    let gravity = ControllerMotionVector(x: 1, y: 0, z: 0)
    let local = RemappingMotionProjection.project(gyro, gravity: gravity, space: .local)
    let player = RemappingMotionProjection.project(gyro, gravity: gravity, space: .player)
    let world = RemappingMotionProjection.project(gyro, gravity: gravity, space: .world)
    #expect(local == RemappingGyroProjection(pitchDegreesPerSecond: 3, yawDegreesPerSecond: 4))
    #expect(player == RemappingGyroProjection(pitchDegreesPerSecond: 3, yawDegreesPerSecond: 0))
    #expect(world == RemappingGyroProjection(pitchDegreesPerSecond: 0, yawDegreesPerSecond: -3))
  }

  @Test func tiltedPlayerYawRelaxesWithoutExceedingCombinedRate() throws {
    let gravity = ControllerMotionVector(x: 0, y: -1, z: -1)
    let gyro = ControllerMotionVector(x: 0, y: 10, z: 0)
    let player = try #require(RemappingMotionProjection.project(
      gyro, gravity: gravity, space: .player
    ))
    let world = try #require(RemappingMotionProjection.project(
      gyro, gravity: gravity, space: .world
    ))
    #expect(abs(world.yawDegreesPerSecond - 10 / sqrt(2)) < 1e-9)
    #expect(abs(player.yawDegreesPerSecond - 14.1 / sqrt(2)) < 1e-9)
    let capped = RemappingMotionProjection.project(
      gyro, gravity: gravity, space: .player, yawRelaxation: 10
    )
    #expect(capped?.yawDegreesPerSecond == 10)
  }

  @Test func degenerateGravityAndInvalidTuningAreRejected() {
    let gyro = ControllerMotionVector(x: 1, y: 2, z: 3)
    let zero = ControllerMotionVector(x: 0, y: 0, z: 0)
    #expect(RemappingMotionProjection.project(gyro, gravity: zero, space: .world) == nil)
    #expect(RemappingMotionProjection.project(gyro, gravity: zero, space: .local) != nil)
    #expect(RemappingMotionProjection.project(
      gyro, gravity: zero, space: .local, yawRelaxation: .nan
    ) == nil)
    #expect(RemappingMotionProjection.project(
      gyro, gravity: zero, space: .local, sideReductionThreshold: -1
    ) == nil)
  }
}
