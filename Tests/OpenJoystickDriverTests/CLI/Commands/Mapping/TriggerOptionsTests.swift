import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct TriggerOptionsTests {
  @Test func createsPartiallyUpdatesAndRemovesOneTriggerMapping() throws {
    let original = [
      RemappingTriggerMapping(source: .left),
      RemappingTriggerMapping(source: .right, mode: .preferFull, softThreshold: 0.2),
    ]
    let updated = try MappingProfileEditor.triggerMappings(
      MappingOptions([
        "--trigger-source", "right", "--trigger-mode", "responsive_prefer_full_combined",
        "--trigger-full-threshold", "0.8", "--trigger-hysteresis", "0.04",
        "--trigger-skip-window-ms", "120", "--trigger-passthrough", "true",
      ]),
      defaultValue: original
    )
    #expect(updated[0] == original[0])
    #expect(updated[1] == RemappingTriggerMapping(
      source: .right,
      mode: .responsivePreferFullCombined,
      softThreshold: 0.2,
      fullThreshold: 0.8,
      hysteresis: 0.04,
      skipWindowMs: 120,
      passthrough: true
    ))
    #expect(try MappingProfileEditor.triggerMappings(
      MappingOptions(["--trigger-source", "right", "--trigger-mode", "none"]),
      defaultValue: updated
    ) == [original[0]])
  }

  @Test(arguments: [
    ["--trigger-mode", "exclusive"],
    ["--trigger-source", "middle"],
    ["--trigger-source", "left", "--trigger-mode", "unknown"],
    ["--trigger-source", "left", "--trigger-mode", "none", "--trigger-passthrough", "true"],
    ["--trigger-source", "left", "--trigger-passthrough", "yes"],
    ["--trigger-source", "left", "--trigger-soft-threshold", "nan"],
    [
      "--trigger-source", "left", "--trigger-soft-threshold", "0.9",
      "--trigger-full-threshold", "0.8",
    ],
  ])
  func rejectsInvalidOptions(arguments: [String]) throws {
    #expect(throws: (any Error).self) {
      try MappingProfileEditor.triggerMappings(MappingOptions(arguments))
    }
  }
}
