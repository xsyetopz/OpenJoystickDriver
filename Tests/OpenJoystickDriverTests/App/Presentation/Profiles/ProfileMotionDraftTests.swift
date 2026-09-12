import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct ProfileMotionDraftTests {
  @Test func numericEntryUsesCompleteTextAndPreservesUneditedFields() throws {
    let form = ProfileMotionDraft(.default)
    var text = form.numericText
    text["yawSensitivity"] = " 2,125 "
    let edited = try form.applyingNumericText(text, decimalSeparator: ",")
    #expect(edited.yawSensitivity == 2.125)
    #expect(edited.pitchSensitivity == 1)
    #expect(form.yawSensitivity == 1)
    for invalid in ["", "2x", "nan", "inf", "1,2,3", "101"] {
      text["yawSensitivity"] = invalid
      #expect(throws: RemappingMotionTuningError.self) {
        try form.applyingNumericText(text, decimalSeparator: ",")
      }
    }
    text.removeValue(forKey: "yawSensitivity")
    #expect(throws: RemappingMotionTuningError.self) {
      try form.applyingNumericText(text)
    }
  }

  @Test func formPreservesAllFieldsAndEditsRemainLocalUntilValidated() throws {
    let original = RemappingMotionTuning(
      space: .world,
      pitchSensitivity: 2.5,
      yawSensitivity: 3.5,
      invertPitch: true,
      invertYaw: true,
      smoothingHalfTimeMs: 17,
      thresholdDegreesPerSecond: 0.25,
      automaticBias: false,
      yawRelaxation: 1.8,
      sideReductionThreshold: 0.2,
      gravityCorrectionRate: 4,
      lean: RemappingMotionLean(thresholdDegrees: 20, hysteresisDegrees: 3),
      steering: RemappingMotionSteering(
        output: .rightStickX,
        deadzoneDegrees: 4,
        fullScaleDegrees: 40,
        responseExponent: 2,
        inverted: true
      )
    )
    var form = ProfileMotionDraft(original)
    #expect(try form.validatedTuning() == original)
    form.yawSensitivity = 7
    form.invertPitch = false
    let edited = try form.validatedTuning()
    #expect(edited.yawSensitivity == 7 && !edited.invertPitch)
    #expect(edited.smoothingHalfTimeMs == original.smoothingHalfTimeMs)
    #expect(edited.lean == original.lean && edited.steering == original.steering)
    #expect(original.yawSensitivity == 3.5 && original.invertPitch)
    form.gravityCorrectionRate = .infinity
    #expect(throws: RemappingMotionTuningError.invalidField("gravity_correction_rate")) {
      try form.validatedTuning()
    }
    form = ProfileMotionDraft(.default)
    #expect(try form.validatedTuning() == .default)
  }
}
