import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingActionCollectionTests {
  @Test func oneControlDrivesMixedActionsWithIndependentReleaseBehavior() throws {
    let profile = profile(binding: RemappingBinding(
      source: .button(.south),
      destination: .gamepadButton(.north),
      additionalActions: [RemappingAction(
        destination: .keyboard(key: .a, modifiers: []), behavior: .toggle
      )]
    ))
    try profile.validate()
    #expect(profile.requiresSystemInputAccess)
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ) == [
      .gamepad(RemappingGamepadState(buttons: [.north]), identifier), .system(.keyDown(.a))
    ])
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1
    ) == [.gamepad(.neutral, identifier)])
    #expect(state.releaseController(identifier) == [.system(.keyUp(.a))])
  }

  @Test func independentHoldDeadlinesDoNotReplaceEachOther() {
    let profile = profile(binding: RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: []),
      longHold: RemappingLongHold(durationMs: 100, destination: .keyboard(key: .b, modifiers: [])),
      additionalActions: [RemappingAction(
        destination: .keyboard(key: .c, modifiers: []),
        longHold: RemappingLongHold(durationMs: 200, destination: .keyboard(key: .d, modifiers: []))
      )]
    ))
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    #expect(state.tick(at: 100_000_000) == [.system(.keyDown(.b))])
    #expect(state.tick(at: 200_000_000) == [.system(.keyDown(.d))])
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 200_000_001
    ) == [.system(.keyUp(.b)), .system(.keyUp(.d))])
  }

  @Test func continuousAdditionalActionUsesTheSameInputSample() {
    let profile = profile(binding: RemappingBinding(
      source: .axis(.leftStickX),
      destination: .gamepadAxis(.rightStickX),
      axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1),
      additionalActions: [RemappingAction(destination: .mouseMovement(.x))]
    ))
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.leftStickChanged(x: 0.5, y: 0)], from: identifier, profile: profile, at: 0
    ) == [.gamepad(RemappingGamepadState(axes: [.rightStickX: 0.5]), identifier)])
    #expect(state.tick(at: 1) == [.system(.mouseMoved(axis: .x, amount: 0.5))])
    _ = state.releaseController(identifier)
    #expect(!state.hasScheduledOutput)
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(binding: RemappingBinding) -> RemappingProfile {
    RemappingProfile(
      name: "Collection",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [binding]
    )
  }
}
