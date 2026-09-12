import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingActionTests {
  @Test func actionCollectionPreservesOrderAndIndependentBehavior() throws {
    let actions = [
      RemappingAction(destination: .keyboard(key: .b, modifiers: []), behavior: .toggle),
      RemappingAction(destination: .mouseButton(.left), behavior: .pulse, pulseDurationMs: 250)
    ]
    let profile = profile(actions: actions)
    try profile.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    #expect(decoded.bindings.first?.additionalActions == actions)
  }

  @Test func duplicateActionIdentityIsRejected() {
    let action = RemappingAction(destination: .keyboard(key: .a, modifiers: []))
    #expect(throws: RemappingValidationError.duplicateBindingID(action.id)) {
      try profile(actions: [action, action]).validate()
    }
  }

  @Test func additionalVirtualActionRequiresVirtualOutputPolicy() {
    #expect(throws: RemappingValidationError.virtualOutputRequired) {
      try profile(actions: [RemappingAction(destination: .gamepadButton(.north))]).validate()
    }
  }

  private func profile(actions: [RemappingAction]) -> RemappingProfile {
    RemappingProfile(
      name: "Actions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        additionalActions: actions
      )]
    )
  }
}
