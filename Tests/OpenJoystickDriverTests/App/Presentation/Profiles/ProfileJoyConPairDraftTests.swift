import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileJoyConPairDraftTests {
  @Test
  func ordinaryEditorMutationsPreservePairSettings() throws {
    let profile = RemappingProfile(
      name: "Pair",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
      applicationScope: .global,
      joyConPair: RemappingJoyConPairSettings(gyroSelection: .left),
      bindings: []
    )
    let draft = RuntimeProfileDraft(profile: profile)

    let edited = try draft.settingTouchMappings([]).settingStickMappings([])

    #expect(edited.profile.joyConPair == profile.joyConPair)
    #expect(try edited.validatedProfile().joyConPair == profile.joyConPair)
  }
}
