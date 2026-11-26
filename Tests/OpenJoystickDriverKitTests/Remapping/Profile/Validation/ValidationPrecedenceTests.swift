import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Profile validation reports the first failing check in a fixed order.
struct RemappingValidationPrecedenceTests {
  private func profile(
    name: String = "Precedence",
    applicationScope: RemappingApplicationScope = .global,
    gyroOutput: RemappingGyroOutput = .default,
    stickMappings: [RemappingStickMapping] = [],
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: applicationScope,
      gyroOutput: gyroOutput,
      stickMappings: stickMappings,
      bindings: bindings
    )
  }

  @Test
  func profileNameWinsOverDuplicateStickMapping() {
    let value = profile(
      name: "",
      stickMappings: [RemappingStickMapping(source: .left), RemappingStickMapping(source: .left)]
    )
    #expect(throws: RemappingValidationError.invalidProfileName) { try value.validate() }
  }

  @Test
  func duplicateStickMappingWinsOverVirtualOutputRequirement() {
    let value = profile(
      gyroOutput: RemappingGyroOutput(mode: .leftStick),
      stickMappings: [RemappingStickMapping(source: .left), RemappingStickMapping(source: .left)]
    )
    #expect(throws: RemappingValidationError.duplicateStickMapping(.left)) { try value.validate() }
  }

  @Test
  func virtualOutputRequirementWinsOverApplicationScope() {
    let value = profile(
      applicationScope: .application(appIDs: []),
      gyroOutput: RemappingGyroOutput(mode: .leftStick)
    )
    #expect(throws: RemappingValidationError.virtualOutputRequired) { try value.validate() }
  }

  @Test
  func applicationScopeWinsOverBindingBehavior() {
    let value = profile(
      applicationScope: .application(appIDs: []),
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .macro(UUID()),
          pulseDurationMs: 0
        )
      ]
    )
    #expect(throws: RemappingValidationError.noAppIDs) { try value.validate() }
  }

  @Test
  func bindingBehaviorWinsOverUnknownMacro() {
    let value = profile(bindings: [
      RemappingBinding(source: .button(.south), destination: .macro(UUID()), pulseDurationMs: 0)
    ])
    #expect(throws: RemappingValidationError.bindingBehaviorConflict(index: 0)) {
      try value.validate()
    }
  }
}
