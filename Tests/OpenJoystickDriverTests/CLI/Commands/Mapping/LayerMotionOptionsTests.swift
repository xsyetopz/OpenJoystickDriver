import OpenJoystickDriverKit
import Testing
@testable import OpenJoystickDriver

struct LayerMotionOptionsTests {
  @Test func layerMotionPreservesProfileIdentity() throws {
    let layer = RemappingLayer(name: "Aim", activationMode: .hold, activator: .button(.east))
    let binding = RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .space, modifiers: [])
    )
    let original = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding],
      layers: [layer]
    )
    let edited = try MappingProfileEditor.settingLayerMotion(
      original, layerID: layer.id, options: MappingOptions(["--motion-yaw-sensitivity", "2"])
    )
    #expect(edited.schemaVersion == RemappingProfile.currentSchemaVersion)
    #expect(edited.id == original.id)
    #expect(edited.device == original.device)
    #expect(edited.bindings == original.bindings)
    #expect(edited.layers[0].id == layer.id)
    #expect(original.schemaVersion == RemappingProfile.currentSchemaVersion)
    #expect(original.layers[0].motionTuning == nil)
    let cleared = try MappingProfileEditor.settingLayerMotion(
      original, layerID: layer.id, options: MappingOptions(["--clear"], flags: ["--clear"])
    )
    #expect(cleared == original)
  }

  @Test func layerMotionUpdatesPreserveBaseAndClearOverride() throws {
    let layer = RemappingLayer(name: "Aim", activationMode: .hold, activator: .button(.east))
    let base = RemappingMotionTuning(space: .world, pitchSensitivity: 3)
    let profile = RemappingProfile(
      name: "Motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: base,
      bindings: [],
      layers: [layer]
    )
    let updated = try MappingProfileEditor.settingLayerMotion(
      profile, layerID: layer.id, options: MappingOptions(["--motion-yaw-sensitivity", "0.5"])
    )
    #expect(updated.motionTuning == base)
    #expect(updated.layers[0].motionTuning?.pitchSensitivity == 3)
    #expect(updated.layers[0].motionTuning?.yawSensitivity == 0.5)
    #expect(updated.layers[0].id == layer.id)
    let cleared = try MappingProfileEditor.settingLayerMotion(
      updated, layerID: layer.id, options: MappingOptions(["--clear"], flags: ["--clear"])
    )
    #expect(cleared.layers[0].motionTuning == nil)
    #expect(cleared == profile)
    let conflicting = try MappingOptions(
      ["--clear", "--motion-yaw-sensitivity", "2"], flags: ["--clear"]
    )
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.settingLayerMotion(profile, layerID: layer.id, options: conflicting)
    }
  }
}
