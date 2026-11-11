import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingExtraButtonTests {
  @Test(arguments: [
    (Control.leftPaddle2, Control.leftPaddle2), (Control.rightPaddle2, .rightPaddle2),
    (Control.leftTrackpadClick, .leftTrackpadClick),
    (Control.rightTrackpadClick, .rightTrackpadClick),
    (Control.auxiliary3, .auxiliary3), (Control.auxiliary4, .auxiliary4),
    (Control.auxiliary5, .auxiliary5), (Control.auxiliary6, .auxiliary6),
    (Control.auxiliary1, .auxiliary1), (Control.auxiliary2, .auxiliary2),
    (Control.leftPaddle1, .leftPaddle1), (Control.rightPaddle1, .rightPaddle1),
  ])
  func extraButtonCanHoldAndReleaseAKeyboardAction(
    physical: Control,
    source: Control
  ) throws {
    let profile = profile(source: source)
    try profile.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(profile)
    )
    var engine = RemappingEngineState()
    let identifier = LogicalControllerID(vendorID: 1, productID: 2)
    #expect(
      engine.process(inputs: [.press(physical)], from: identifier, profile: decoded, at: 0) == [
        .system(.keyDown(.space))
      ]
    )
    #expect(
      engine.process(inputs: [.release(physical)], from: identifier, profile: decoded, at: 1) == [
        .system(.keyUp(.space))
      ]
    )
    #expect(engine.drain().isEmpty)
  }

  @Test(arguments: [
    Control.leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick, .auxiliary3,
    .auxiliary4, .auxiliary5,
    .auxiliary6, .auxiliary1, .auxiliary2, .leftPaddle1, .rightPaddle1,
  ])
  func inputOnlyButtonsCannotBeVirtualDestinations(_ button: Control) {
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

  /// The classic Steam Controller's right pad is its right stick, so its pad click is R3.
  ///
  /// The Steam Deck and the Steam Triton have a real R3, so their pad click is a control no persona
  /// carries.
  @Test(arguments: [
    (0x1102, true), (0x1205, false), (0x1303, false),
  ])
  func rightPadPassthroughIsConsumedByAnExplicitMapping(
    productID: UInt16,
    padIsRightStick: Bool
  ) throws {
    let identifier = LogicalControllerID(vendorID: 0x28DE, productID: productID)
    for mapped in [false, true] {
      let bindings = mapped ? profile(source: .rightTrackpadClick).bindings : []
      let profile = RemappingProfile(
        name: "Pad passthrough",
        device: RemappingDeviceScope(vendorID: 0x28DE, productID: productID),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
        bindings: bindings
      )
      try profile.validate()
      var engine = RemappingEngineState()
      let press = engine.process(
        inputs: [.press(.rightTrackpadClick)],
        from: identifier,
        profile: profile,
        at: 0
      )
      let release = engine.process(
        inputs: [.release(.rightTrackpadClick)],
        from: identifier,
        profile: profile,
        at: 1
      )
      if mapped {
        #expect(press == [.system(.keyDown(.space))])
        #expect(release == [.system(.keyUp(.space))])
      } else if padIsRightStick {
        #expect(press == [.gamepad(RemappingGamepadState(buttons: [.rightStickClick]), identifier)])
        #expect(release == [.gamepad(.neutral, identifier)])
      } else {
        #expect(press.allSatisfy { $0 == .gamepad(.neutral, identifier) })
        #expect(release.allSatisfy { $0 == .gamepad(.neutral, identifier) })
      }
    }
  }

  private func profile(source: Control) -> RemappingProfile {
    RemappingProfile(
      name: "Extra button",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(source),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
  }
}
