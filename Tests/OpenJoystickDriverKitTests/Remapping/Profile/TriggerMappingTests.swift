import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct TriggerMappingTests {
  @Test func allModesRoundTripInTheSchemaThreeProfile() throws {
    for mode in RemappingDualStageTriggerMode.allCases {
      let mapping = RemappingTriggerMapping(
        source: .left,
        mode: mode,
        softThreshold: 0.2,
        fullThreshold: 0.8,
        hysteresis: 0.1,
        skipWindowMs: 120,
        passthrough: true
      )
      let profile = RemappingProfile(
        name: "Trigger",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        triggerMappings: [mapping],
        bindings: [RemappingBinding(
          source: .triggerStage(.left, .soft),
          destination: .keyboard(key: .a, modifiers: [])
        )]
      )
      try profile.validate()
      let data = try JSONEncoder().encode(profile)
      #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
    }
  }

  @Test func validationRequiresUniqueValidMappingsForStageSources() {
    let mapping = RemappingTriggerMapping(source: .right)
    #expect(throws: RemappingValidationError.duplicateTriggerMapping(.right)) {
      try profile(mappings: [mapping, mapping]).validate()
    }
    #expect(throws: RemappingValidationError.invalidTriggerMapping(.right)) {
      try profile(mappings: [RemappingTriggerMapping(
        source: .right, softThreshold: 0.9, fullThreshold: 0.8
      )]).validate()
    }
    #expect(throws: RemappingValidationError.triggerStageWithoutMapping(.right)) {
      try profile(mappings: []).validate()
    }
  }

  private func profile(mappings: [RemappingTriggerMapping]) -> RemappingProfile {
    RemappingProfile(
      name: "Trigger",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      triggerMappings: mappings,
      bindings: [RemappingBinding(
        source: .triggerStage(.right, .full),
        destination: .keyboard(key: .b, modifiers: [])
      )]
    )
  }
}
