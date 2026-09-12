import Testing
import OpenJoystickDriverKit

@testable import OpenJoystickDriver

struct MotionOptionsTests {
  @Test func gyroConsumptionCanBeDisabledAndSurvivesPartialUpdates() throws {
    let options = try MappingOptions(["--gyro-consume-activation", "false"])
    let output = try MappingProfileEditor.gyroOutput(options)
    #expect(!output.consumesActivationSource)
    let unchanged = try MappingProfileEditor.gyroOutput(
      MappingOptions([]), defaultValue: output
    )
    #expect(unchanged == output)
    let invalid = try MappingOptions(["--gyro-consume-activation", "yes"])
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.gyroOutput(invalid)
    }
  }

  @Test func partialUpdatePreservesOtherSettingsAndCanDisableBooleans() throws {
    let original = RemappingMotionTuning(
      space: .world, pitchSensitivity: 3, invertYaw: true, smoothingHalfTimeMs: 20
    )
    let options = try MappingOptions([
      "--motion-yaw-sensitivity", "4", "--motion-invert-yaw", "false",
      "--motion-automatic-bias", "false"
    ])
    let updated = try MappingProfileEditor.motionTuning(options, defaultValue: original)
    #expect(updated.space == .world)
    #expect(updated.pitchSensitivity == 3)
    #expect(updated.yawSensitivity == 4)
    #expect(updated.smoothingHalfTimeMs == 20)
    #expect(!updated.invertYaw && !updated.automaticBias)
  }

  @Test func leanAndSteeringCanBeEnabledUpdatedAndRemovedIndependently() throws {
    let configured = try MappingProfileEditor.motionTuning(MappingOptions([
      "--motion-lean", "true", "--motion-lean-threshold-degrees", "20",
      "--motion-lean-hysteresis-degrees", "3", "--motion-steering-output", "right_stick_x",
      "--motion-steering-deadzone-degrees", "4", "--motion-steering-full-scale-degrees", "40",
      "--motion-steering-response-exponent", "2", "--motion-steering-inverted", "true",
    ]))
    #expect(configured.lean == RemappingMotionLean(thresholdDegrees: 20, hysteresisDegrees: 3))
    #expect(configured.steering == RemappingMotionSteering(
      output: .rightStickX,
      deadzoneDegrees: 4,
      fullScaleDegrees: 40,
      responseExponent: 2,
      inverted: true
    ))
    let noLean = try MappingProfileEditor.motionTuning(
      MappingOptions(["--motion-lean", "false"]), defaultValue: configured
    )
    #expect(noLean.lean == nil && noLean.steering == configured.steering)
    let removed = try MappingProfileEditor.motionTuning(
      MappingOptions(["--motion-steering-output", "none"]), defaultValue: noLean
    )
    #expect(removed.lean == nil && removed.steering == nil)
  }

  @Test(arguments: [
    ["--motion-space", "unknown"],
    ["--motion-invert-pitch", "yes"],
    ["--motion-yaw-sensitivity", "nan"],
    ["--motion-smoothing-half-time-ms", "-1"],
    ["--motion-side-reduction-threshold", "2"],
    ["--motion-lean", "false", "--motion-lean-threshold-degrees", "10"],
    ["--motion-steering-output", "none", "--motion-steering-inverted", "true"],
    ["--motion-steering-output", "left_stick_x", "--motion-steering-full-scale-degrees", "2"]
  ])
  func invalidOptionsAreRejected(arguments: [String]) throws {
    let options = try MappingOptions(arguments)
    #expect(throws: (any Error).self) {
      try MappingProfileEditor.motionTuning(options)
    }
  }
}
