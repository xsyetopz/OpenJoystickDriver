import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct BindingTemplateTests {
  private static let device = RemappingDeviceScope(vendorID: 1, productID: 2)

  private static func capabilities(_ controls: Set<Control>) -> ControllerProfileCapabilities {
    ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(controls: controls),
      physicalOutput: .none
    )
  }

  private static func made(
    _ template: RemappingBindingTemplate,
    controls: Set<Control>
  ) -> RemappingBindingTemplate.Made {
    template.profile(
      name: "Template",
      device: device,
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared),
      capabilities: capabilities(controls)
    )
  }

  @Test
  func everyTemplateBindsItsControlsByStandardNameOnAFullController() throws {
    for template in RemappingBindingTemplate.allCases {
      let made = Self.made(template, controls: Set(Control.allCases))
      #expect(made.skipped.isEmpty)
      #expect(made.profile.bindings.count == template.controls.count)
      try made.profile.validate()
    }
  }

  @Test
  func theKeyboardNavigationTemplateBindsTheDpadToArrowKeys() {
    let made = Self.made(.keyboardNavigation, controls: Set(Control.allCases))
    let up = made.profile.bindings.first { $0.source == .dpad(.up) }
    #expect(up?.destination == .keyboard(key: .arrowUp, modifiers: []))
  }

  @Test
  func aTemplateSkipsAControlTheControllerLacksAndListsIt() {
    let controls = Set(Control.allCases).subtracting([.dpadLeft, .east])
    let made = Self.made(.keyboardNavigation, controls: controls)
    #expect(Set(made.skipped) == [.dpadLeft, .east])
    #expect(
      made.profile.bindings.count == RemappingBindingTemplate.keyboardNavigation.controls.count - 2
    )
    #expect(!made.profile.bindings.contains { $0.source == .dpad(.left) })
  }

  @Test
  func aTemplateForAControllerWithNoneOfItsControlsSkipsAllOfThem() {
    let made = Self.made(.mouseClicks, controls: [])
    #expect(made.profile.bindings.isEmpty)
    #expect(made.skipped == RemappingBindingTemplate.mouseClicks.controls)
  }
}
