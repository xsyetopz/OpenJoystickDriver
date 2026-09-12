import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct TrackballOptionsTests {
  @Test
  func virtualMotionOptionIsTypedAndPreserved() throws {
    let enabled = try MappingProfileEditor.gyroOutput(
      MappingOptions(["--gyro-virtual-motion", "true"])
    )
    #expect(enabled.virtualMotion)
    let preserved = try MappingProfileEditor.gyroOutput(MappingOptions([]), defaultValue: enabled)
    #expect(preserved.virtualMotion)
    #expect(throws: (any Error).self) {
      try MappingProfileEditor.gyroOutput(MappingOptions(["--gyro-virtual-motion", "yes"]))
    }
  }

  @Test
  func createsUpdatesPreservesAndRemovesTrackball() throws {
    let created = try MappingProfileEditor.gyroOutput(
      MappingOptions([
        "--gyro-output", "mouse", "--gyro-trackball-source", "button:south",
        "--gyro-trackball-axes", "yaw", "--gyro-trackball-decay", "2", "--gyro-trackball-consume",
        "false",
      ])
    )
    let trackball = try #require(created.trackball)
    #expect(trackball.source == .button(.south))
    #expect(trackball.axes == .yaw)
    #expect(trackball.decayHalvingsPerSecond == 2)
    #expect(!trackball.consumesSource)
    let preserved = try MappingProfileEditor.gyroOutput(
      MappingOptions(["--gyro-pointer-points-per-degree", "3"]),
      defaultValue: created
    )
    #expect(preserved.trackball == trackball)
    let updated = try MappingProfileEditor.gyroOutput(
      MappingOptions(["--gyro-trackball-decay", "0"]),
      defaultValue: created
    )
    #expect(updated.trackball?.decayHalvingsPerSecond == 0)
    #expect(updated.trackball?.axes == .yaw)
    let removed = try MappingProfileEditor.gyroOutput(
      MappingOptions(["--gyro-trackball-source", "none"]),
      defaultValue: created
    )
    #expect(removed.trackball == nil)
    #expect(removed.mode == .mouse)
  }

  @Test(arguments: [
    ["--gyro-trackball-decay", "2"],
    ["--gyro-trackball-source", "none", "--gyro-trackball-axes", "yaw"],
    ["--gyro-trackball-source", "axis:left_stick_x"],
    ["--gyro-trackball-source", "button:south", "--gyro-trackball-decay", "nan"],
    ["--gyro-trackball-source", "button:south", "--gyro-trackball-decay", "-1"],
    ["--gyro-trackball-source", "button:south", "--gyro-trackball-axes", "invalid"],
    ["--gyro-trackball-source", "button:south", "--gyro-trackball-consume", "yes"],
  ])
  func rejectsInvalidOptions(arguments: [String]) throws {
    let options = try MappingOptions(arguments)
    #expect(throws: (any Error).self) { try MappingProfileEditor.gyroOutput(options) }
  }
}
