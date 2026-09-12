import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct StickOptionsTests {
  @Test func partialUpdatePreservesOtherStickAndProfileSettings() throws {
    let original = RemappingProfile(
      name: "Sticks",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      gyroOutput: RemappingGyroOutput(mode: .mouse),
      stickMappings: [
        RemappingStickMapping(source: .right, mode: .flick, pointerPointsPerDegree: 3),
        RemappingStickMapping(source: .left, aimDegreesPerSecond: 200)
      ],
      bindings: []
    )
    let updated = try MappingProfileEditor.updating(original, options: MappingOptions([
      "--stick-source", "right", "--stick-flick-duration-ms", "75",
      "--stick-inner-deadzone", "0.2", "--stick-invert-y", "true"
    ]))
    #expect(updated.id == original.id)
    #expect(updated.gyroOutput == original.gyroOutput)
    #expect(updated.stickMappings[1] == original.stickMappings[1])
    let right = updated.stickMappings[0]
    #expect(right.mode == .flick)
    #expect(right.pointerPointsPerDegree == 3)
    #expect(right.flickDurationMs == 75)
    #expect(right.tuning.innerDeadzone == 0.2)
    #expect(right.tuning.invertY)
    let removed = try MappingProfileEditor.updating(updated, options: MappingOptions([
      "--stick-source", "right", "--stick-mode", "none"
    ]))
    #expect(removed.stickMappings == [original.stickMappings[1]])
  }

  @Test func createsMappingWithDefaults() throws {
    let mappings = try MappingProfileEditor.stickMappings(MappingOptions([
      "--stick-source", "left", "--stick-mode", "rotate_only"
    ]))
    #expect(mappings == [RemappingStickMapping(source: .left, mode: .rotateOnly)])
  }

  @Test func advancedModesPreserveTypedDirectionOutputAndPassthrough() throws {
    let mappings = try MappingProfileEditor.stickMappings(MappingOptions([
      "--stick-source", "right", "--stick-mode", "scroll_wheel",
      "--stick-scroll-degrees-per-line", "12", "--stick-scroll-axis", "horizontal",
      "--stick-rotation-direction", "clockwise", "--stick-pointer-radius-points", "240",
      "--stick-steering-degrees-at-full-scale", "360",
      "--stick-steering-return-degrees-per-second", "120",
      "--stick-steering-output", "right_stick_x", "--stick-passthrough", "true",
    ]))
    let mapping = try #require(mappings.first)
    #expect(mapping.mode == .scrollWheel)
    #expect(mapping.scrollDegreesPerLine == 12)
    #expect(mapping.scrollAxis == .horizontal)
    #expect(mapping.rotationDirection == .clockwise)
    #expect(mapping.pointerRadiusPoints == 240)
    #expect(mapping.steeringOutput == .rightStickX)
    #expect(mapping.passthrough)
  }

  @Test(arguments: [
    ["--stick-mode", "aim"],
    ["--stick-source", "invalid"],
    ["--stick-source", "left", "--stick-mode", "invalid"],
    ["--stick-source", "left", "--stick-mode", "none", "--stick-invert-x", "true"],
    ["--stick-source", "left", "--stick-invert-x", "yes"],
    ["--stick-source", "left", "--stick-aim-degrees-per-second", "nan"],
    ["--stick-source", "left", "--stick-flick-duration-ms", "-1"],
    ["--stick-source", "left", "--stick-scroll-axis", "diagonal"],
    ["--stick-source", "left", "--stick-passthrough", "yes"],
    ["--stick-source", "left", "--stick-pointer-radius-points", "0"],
    ["--stick-source", "left", "--stick-inner-deadzone", "0.8", "--stick-outer-deadzone", "0.3"]
  ])
  func rejectsInvalidOptions(arguments: [String]) throws {
    let options = try MappingOptions(arguments)
    #expect(throws: (any Error).self) { try MappingProfileEditor.stickMappings(options) }
  }
}
