import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingExtraButtonTests {
  @Test(arguments: [
    (Button.leftGrip, RemappingButton.leftGrip),
    (Button.rightGrip, RemappingButton.rightGrip),
    (Button.leftPadClick, RemappingButton.leftPadClick),
    (Button.rightPadClick, RemappingButton.rightPadClick),
    (Button.leftSL, RemappingButton.leftSL),
    (Button.leftSR, RemappingButton.leftSR),
    (Button.rightSL, RemappingButton.rightSL),
    (Button.rightSR, RemappingButton.rightSR),
    (Button.leftFunction, RemappingButton.leftFunction),
    (Button.rightFunction, RemappingButton.rightFunction),
    (Button.leftPaddle, RemappingButton.leftPaddle),
    (Button.rightPaddle, RemappingButton.rightPaddle)
  ]) func extraButtonCanHoldAndReleaseAKeyboardAction(
    physical: Button,
    source: RemappingButton
  ) throws {
    let profile = profile(source: source)
    try profile.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    var engine = RemappingEngineState()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    #expect(engine.process(
      events: [.buttonPressed(physical)], from: identifier, profile: decoded, at: 0
    ) == [.system(.keyDown(.space))])
    #expect(engine.process(
      events: [.buttonReleased(physical)], from: identifier, profile: decoded, at: 1
    ) == [.system(.keyUp(.space))])
    #expect(engine.drain().isEmpty)
  }

  @Test(arguments: [
    RemappingButton.leftGrip, .rightGrip, .leftPadClick, .rightPadClick,
    .leftSL, .leftSR, .rightSL, .rightSR,
    .leftFunction, .rightFunction, .leftPaddle, .rightPaddle
  ]) func inputOnlyButtonsCannotBeVirtualDestinations(_ button: RemappingButton) {
    let invalid = RemappingProfile(
      name: "Invalid output",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(button))]
    )
    #expect(throws: RemappingValidationError.unsupportedGamepadButton(button)) {
      try invalid.validate()
    }
    #expect(RemappingGamepadState(buttons: [button]) == .neutral)
  }

  @Test func rightPadPassthroughIsConsumedByAnExplicitMapping() throws {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    for mapped in [false, true] {
      let bindings = mapped ? profile(source: .rightPadClick).bindings : []
      let profile = RemappingProfile(
        name: "Pad passthrough",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
        bindings: bindings
      )
      try profile.validate()
      var engine = RemappingEngineState()
      let press = engine.process(
        events: [.buttonPressed(.rightPadClick)], from: identifier, profile: profile, at: 0
      )
      let release = engine.process(
        events: [.buttonReleased(.rightPadClick)], from: identifier, profile: profile, at: 1
      )
      if mapped {
        #expect(press == [.system(.keyDown(.space))])
        #expect(release == [.system(.keyUp(.space))])
      } else {
        #expect(press == [.gamepad(RemappingGamepadState(buttons: [.rightStick]), identifier)])
        #expect(release == [.gamepad(.neutral, identifier)])
      }
    }
  }

  private func profile(source: RemappingButton) -> RemappingProfile {
    RemappingProfile(
      name: "Extra button",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(source), destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
  }
}
