import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct RuntimeLayerMotionDraftTests {
  @Test func nativeLayerMotionPreservesAndClears() throws {
    let binding = RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .space, modifiers: [])
    )
    let layer = RemappingLayer(
      name: "Aim", activationMode: .hold, activator: .button(.east), bindings: [binding]
    )
    let original = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      layers: [layer]
    )
    let draft = RuntimeProfileDraft(profile: original)
    let tuning = RemappingMotionTuning(yawSensitivity: 0.5)
    let edited = try draft.settingLayerMotionTuning(tuning, for: layer.id)
    #expect(edited.profile.schemaVersion == RemappingProfile.currentSchemaVersion)
    #expect(edited.profile.id == original.id)
    #expect(edited.profile.layers[0].bindings == [binding])
    #expect(edited.profile.layers[0].motionTuning == tuning)
    #expect(edited.profile.motionTuning == original.motionTuning)
    let removedBinding = try edited.removingLayerBinding(layerID: layer.id, bindingID: binding.id)
    #expect(removedBinding.profile.layers[0].motionTuning == tuning)
    let cleared = try edited.settingLayerMotionTuning(nil, for: layer.id)
    #expect(cleared.profile.layers[0] == layer)
    #expect(draft.profile == original)
    #expect(throws: RuntimeProfileDraftError.self) {
      try edited.settingLayerMotionTuning(RemappingMotionTuning(yawSensitivity: -1), for: layer.id)
    }
  }
}
