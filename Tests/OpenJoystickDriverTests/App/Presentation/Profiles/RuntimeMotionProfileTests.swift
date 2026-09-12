import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RuntimeMotionProfileTests {
  @Test func motionEditValidatesWithoutChangingBindings() throws {
    let binding = RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .space, modifiers: [])
    )
    let original = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding]
    )
    let draft = RuntimeProfileDraft(profile: original)
    let tuning = RemappingMotionTuning(space: .local, yawSensitivity: 4)
    let edited = try draft.settingMotionTuning(tuning)
    #expect(edited.profile.schemaVersion == RemappingProfile.currentSchemaVersion)
    #expect(edited.profile.id == original.id)
    #expect(edited.profile.bindings == original.bindings)
    #expect(edited.profile.device == original.device)
    #expect(edited.profile.motionTuning == tuning)
    #expect(draft.profile == original)
    let error = RemappingValidationError.invalidMotionTuning(.invalidField("pitch_sensitivity"))
    #expect(throws: RuntimeProfileDraftError.validation(error)) {
      try draft.settingMotionTuning(RemappingMotionTuning(pitchSensitivity: -1))
    }
    #expect(try edited.settingMotionTuning(.default).profile.motionTuning == .default)
  }

  @Test func bindingAndMetadataEditsPreserveMotionTuning() throws {
    let tuning = RemappingMotionTuning(space: .world, yawSensitivity: 3, invertPitch: true)
    let destination = RemappingDestination.keyboard(key: .space, modifiers: [])
    let binding = RemappingBinding(source: .button(.south), destination: destination)
    let profile = RemappingProfile(
      name: "Motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: tuning,
      bindings: [binding]
    )
    let draft = RuntimeProfileDraft(profile: profile)
    let renamed = try draft.settingMetadata(
      name: "Renamed", device: profile.device, applicationScope: .global
    )
    #expect(renamed.profile.motionTuning == tuning)
    #expect(try draft.settingOutputPolicy(.systemInput).profile.motionTuning == tuning)
    #expect(try draft.removingBinding(binding.id).profile.motionTuning == tuning)
    let added = try draft.addingBinding(source: .button(.east), destination: destination)
    #expect(added.profile.motionTuning == tuning)
    let cliEdited = try MappingProfileEditor.removingBinding(from: profile, source: .button(.south))
    #expect(cliEdited.motionTuning == tuning)
  }

  @Test func gyroEditsPreserveOtherSettingsAndRejectIncompatibleOutput() throws {
    let binding = RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .space, modifiers: [])
    )
    let original = RemappingProfile(
      name: "Gyro",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding]
    )
    let gyro = RemappingGyroOutput(
      mode: .mouse,
      pointerPointsPerDegree: 3,
      activationMode: .whileHeld,
      activationSource: .button(.east)
    )
    let tuning = RemappingMotionTuning(space: .world, yawSensitivity: 2)
    let draft = RuntimeProfileDraft(profile: original)
    let edited = try draft.settingMotionTuning(tuning, gyroOutput: gyro)
    #expect(edited.profile.gyroOutput == gyro)
    #expect(edited.profile.motionTuning == tuning)
    #expect(edited.profile.bindings == original.bindings)
    #expect(edited.profile.id == original.id)
    let renamed = try edited.settingMetadata(
      name: "Renamed", device: original.device, applicationScope: .global
    )
    #expect(renamed.profile.gyroOutput == gyro)
    #expect(try edited.settingMotionTuning(.default).profile.gyroOutput == gyro)
    #expect(try edited.removingBinding(binding.id).profile.gyroOutput == gyro)
    #expect(throws: RuntimeProfileDraftError.self) {
      try edited.settingMotionTuning(tuning, gyroOutput: RemappingGyroOutput(mode: .rightStick))
    }
    #expect(edited.profile.gyroOutput == gyro)
    #expect(draft.profile == original)
  }

}
