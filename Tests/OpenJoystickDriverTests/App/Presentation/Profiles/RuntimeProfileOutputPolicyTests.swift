import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RuntimeProfileOutputPolicyTests {
  @Test(arguments: RemappingBindingBehavior.allCases)
  func behaviorEditingAndDestinationChangesPreserveSelection(
    behavior: RemappingBindingBehavior
  ) throws {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    let profile = RemappingProfile(
      name: "Behavior",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [binding]
    )
    let edited = try RuntimeProfileDraft(profile: profile).settingBindingBehaviors(
      behavior: behavior,
      pulseDurationMs: behavior == .pulse ? 375 : nil,
      turbo: nil,
      longHold: nil,
      doubleTap: nil,
      for: binding.id
    )
    #expect(edited.profile.bindings.first?.behavior == behavior)
    let changed = try edited.settingDestination(.gamepadDpad(.up), for: binding.id)
    #expect(changed.profile.bindings.first?.behavior == behavior)
    if behavior == .pulse {
      #expect(changed.profile.bindings.first?.pulseDurationMs == 375)
      let decoded = try JSONDecoder().decode(
        RemappingProfile.self, from: JSONEncoder().encode(changed.profile)
      )
      #expect(decoded == changed.profile)
      let switched = try changed.settingBindingBehaviors(
        behavior: .hold, turbo: nil, longHold: nil, doubleTap: nil, for: binding.id
      )
      #expect(switched.profile.bindings.first?.pulseDurationMs
        == RemappingBinding.defaultPulseDurationMs)
    }
  }

  @Test func policyEditsPreserveMappingsAndRejectDisablingRequiredVirtualOutput() throws {
    let profile = RemappingProfile(
      name: "Virtual",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    let draft = RuntimeProfileDraft(profile: profile)
    let edited = try draft.settingOutputPolicy(RemappingOutputPolicy(virtualGamepad: .passthrough))
    #expect(edited.profile.bindings == profile.bindings)
    #expect(edited.profile.id == profile.id)
    #expect(edited.profile.outputPolicy.virtualGamepad == .passthrough)
    #expect(throws: RuntimeProfileDraftError.validation(.virtualOutputRequired)) {
      try edited.settingOutputPolicy(.systemInput)
    }
  }

  @Test func virtualDestinationChoicesRespectSourceKinds() {
    let digital = DestinationOption.options(for: .button(.south)).map(\.destination)
    #expect(digital.contains(.gamepadButton(.north)))
    #expect(digital.contains(.gamepadDpad(.up)))
    #expect(!digital.contains(.gamepadAxis(.leftStickX)))
    let analog = DestinationOption.options(for: .axis(.leftStickX)).map(\.destination)
    #expect(analog.contains(.gamepadAxis(.rightStickX)))
    #expect(!analog.contains(.gamepadButton(.north)))
  }
}
