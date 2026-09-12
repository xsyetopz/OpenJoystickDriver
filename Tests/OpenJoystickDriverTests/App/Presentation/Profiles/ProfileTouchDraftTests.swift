import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileTouchDraftTests {
  @Test func preservesIdentityAndAcceptsLocaleDecimals() throws {
    let mapping = RemappingTouchMapping(
      surface: .right,
      mode: .pointer,
      pointerSensitivity: 750,
      stickRadius: 0.3,
      deadzone: 0.05
    )
    var draft = ProfileTouchDraft(surface: .right, mapping: mapping)
    #expect(try draft.validatedMapping() == mapping)
    draft.pointerSensitivity = "750,5"
    #expect(try draft.validatedMapping(decimalSeparator: ",")?.pointerSensitivity == 750.5)
    draft.deadzone = "2"
    #expect(throws: RemappingValidationError.invalidTouchMapping(.right)) {
      try draft.validatedMapping()
    }
    draft.enabled = false
    #expect(try draft.validatedMapping() == nil)
  }

  @Test func profileEditPreservesOtherContractFields() throws {
    let binding = RemappingBinding(
      source: .touchContact(.primary),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let profile = RemappingProfile(
      name: "Touch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding]
    )
    let mapping = RemappingTouchMapping(surface: .primary, mode: .pointer)
    let edited = try RuntimeProfileDraft(profile: profile).settingTouchMappings([mapping])

    #expect(edited.profile.id == profile.id)
    #expect(edited.profile.bindings == [binding])
    #expect(edited.profile.touchMappings == [mapping])
    #expect(throws: RuntimeProfileDraftError.self) {
      try edited.settingTouchMappings([mapping, mapping])
    }
  }
}
