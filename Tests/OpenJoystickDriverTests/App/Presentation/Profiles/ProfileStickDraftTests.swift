import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct ProfileStickDraftTests {
  @Test func preservesAllSettingsAndAcceptsLocaleDecimals() throws {
    let mapping = RemappingStickMapping(
      source: .right,
      mode: .flickOnly,
      tuning: RemappingStickTuning(
        innerDeadzone: 0.2, outerDeadzone: 0.1, responseExponent: 2, invertX: true, invertY: true
      ),
      aimDegreesPerSecond: 250,
      pointerPointsPerDegree: 4,
      flickDurationMs: 125,
      flickThreshold: 0.8,
      flickHysteresis: 0.2,
      pointerRadiusPoints: 256,
      scrollDegreesPerLine: 12,
      scrollAxis: .horizontal,
      rotationDirection: .clockwise,
      steeringDegreesAtFullScale: 270,
      steeringReturnDegreesPerSecond: 180,
      steeringOutput: .rightStickX,
      passthrough: true
    )
    var draft = ProfileStickDraft(source: .right, mapping: mapping)
    #expect(try draft.validatedMapping() == mapping)
    draft.pointerPointsPerDegree = "4,5"
    #expect(try draft.validatedMapping(decimalSeparator: ",")?.pointerPointsPerDegree == 4.5)
    draft.innerDeadzone = "0,9"
    #expect(throws: RemappingStickTuningError.invalidDeadzones) {
      try draft.validatedMapping(decimalSeparator: ",")
    }
    draft.enabled = false
    #expect(try draft.validatedMapping() == nil)
  }

  @Test func profileEditPreservesBindings() throws {
    let profile = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(
        source: .button(.south), destination: .keyboard(key: .space, modifiers: [])
      )]
    )
    let mapping = RemappingStickMapping(source: .left)
    let edited = try RuntimeProfileDraft(profile: profile).settingStickMappings([mapping])
    #expect(edited.profile.schemaVersion == RemappingProfile.currentSchemaVersion)
    #expect(edited.profile.id == profile.id)
    #expect(edited.profile.bindings == profile.bindings)
    #expect(edited.profile.stickMappings == [mapping])
    let removed = try edited.settingStickMappings([])
    #expect(removed.profile.stickMappings.isEmpty)
    #expect(removed.profile.bindings == profile.bindings)
    #expect(throws: RuntimeProfileDraftError.self) {
      try edited.settingStickMappings([mapping, mapping])
    }
  }

  @Test func newDraftRequiresEnablementAndRejectsInvalidText() throws {
    var draft = ProfileStickDraft(source: .left, mapping: nil)
    #expect(try draft.validatedMapping() == nil)
    draft.enabled = true
    #expect(try draft.validatedMapping() == RemappingStickMapping(source: .left))
    draft.flickDurationMs = "not a number"
    #expect(throws: RemappingStickMappingError.invalidField("flick_duration_ms")) {
      try draft.validatedMapping()
    }
  }
}
