import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileTriggerDraftTests {
  @Test func preservesAllFieldsAcceptsLocaleDecimalsAndCanDisable() throws {
    let mapping = RemappingTriggerMapping(
      source: .right,
      mode: .responsivePreferFullCombined,
      softThreshold: 0.2,
      fullThreshold: 0.8,
      hysteresis: 0.04,
      skipWindowMs: 125,
      passthrough: true
    )
    var draft = ProfileTriggerDraft(source: .right, mapping: mapping)
    #expect(try draft.validatedMapping() == mapping)
    draft.softThreshold = "0,25"
    #expect(try draft.validatedMapping(decimalSeparator: ",")?.softThreshold == 0.25)
    draft.fullThreshold = "0,2"
    #expect(throws: RemappingTriggerMappingError.invalidField("thresholds")) {
      try draft.validatedMapping(decimalSeparator: ",")
    }
    draft.enabled = false
    #expect(try draft.validatedMapping() == nil)
  }

  @Test func profileEditValidatesTheCompleteResult() throws {
    let profile = RemappingProfile(
      name: "Trigger",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(
        source: .triggerStage(.left, .soft),
        destination: .keyboard(key: .space, modifiers: [])
      )]
    )
    #expect(throws: RuntimeProfileDraftError.self) {
      try RuntimeProfileDraft(profile: profile).settingTriggerMappings([])
    }
    let mapping = RemappingTriggerMapping(source: .left)
    let edited = try RuntimeProfileDraft(profile: profile).settingTriggerMappings([mapping])
    #expect(edited.profile.bindings == profile.bindings)
    #expect(edited.profile.triggerMappings == [mapping])
  }
}
