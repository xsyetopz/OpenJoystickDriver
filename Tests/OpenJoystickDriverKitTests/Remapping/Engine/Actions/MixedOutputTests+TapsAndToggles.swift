import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension RemappingMixedOutputTests {
  @Test(arguments: [RemappingBindingBehavior.tapOnPress, .tapOnRelease])

  func edgeTapFiresOnceAndDoesNotLeaveHeldOutput(behavior: RemappingBindingBehavior) async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .gamepadButton(.north),
        behavior: behavior

      )
    ])
    try await engine.process(inputs: [.release(.south)], from: device, using: profile, at: 0)
    #expect(sink.actions.isEmpty)
    // A repeated identical snapshot is not a second press or release.
    try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 1)
    try await engine.process(inputs: [], from: device, using: profile, at: 1)
    #expect(sink.actions.count == (behavior == .tapOnPress ? 2 : 0))
    try await engine.process(inputs: [.release(.south)], from: device, using: profile, at: 2)
    try await engine.process(inputs: [], from: device, using: profile, at: 2)
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device),
      ]
    )
    try await engine.releaseAll(for: device)
    #expect(sink.actions.count == 2)
  }

  @Test

  func lifecycleCancellationDoesNotFireAnArmedReleaseTap() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .gamepadButton(.north),
        behavior: .tapOnRelease
      )
    ])

    try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 0)
    try await engine.releaseAll(for: device)
    try await engine.process(inputs: [.release(.south)], from: device, using: profile, at: 1)
    #expect(sink.actions.isEmpty)
  }

  @Test
  func layerOverrideCancelsReleaseTapEvenWhenOriginalLayerReturns() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(

      name: "Release cancellation",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .gamepadButton(.north),
          behavior: .tapOnRelease

        )
      ],
      layers: [
        RemappingLayer(
          name: "Override",
          activationMode: .hold,
          activator: .button(.east),
          bindings: [
            RemappingBinding(
              source: .button(.south),
              destination: .gamepadButton(.west),
              behavior: .tapOnRelease
            )
          ]
        )
      ]
    )
    try await engine.process(
      inputs: [.press(.south), .press(.east), .release(.east), .release(.south)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(sink.actions.isEmpty)
    try await engine.process(

      inputs: [.press(.south), .release(.south)],
      from: device,
      using: profile,
      at: 1
    )
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device),
      ]
    )

  }

  @Test

  func toggleInputCanCompleteASequenceWithoutLosingItsHeldOutput() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .gamepadButton(.north),
          behavior: .toggle
        )
      ],

      sequences: [
        RemappingSequence(
          sources: [.button(.west), .button(.south)],
          windowMs: 500,
          destination: .gamepadButton(.east)
        )
      ]
    )
    try await engine.process(
      inputs: [.press(.west), .release(.west), .press(.south)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(
      sink.actions.contains(.gamepad(RemappingGamepadState(buttons: [.north, .east]), device))
    )
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [.north]), device))
    try await engine.drain()
  }

  @Test
  func togglePersistsThroughReleaseAndDrainsOnLifecycleChange() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .gamepadButton(.north),
        behavior: .toggle
      )
    ])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    try await engine.process(
      inputs: [.press(.south), .release(.south)],
      from: device,
      using: decoded,
      at: 0
    )
    #expect(sink.actions == [.gamepad(RemappingGamepadState(buttons: [.north]), device)])
    try await engine.process(
      inputs: [.press(.south), .release(.south)],
      from: device,
      using: decoded,
      at: 1
    )
    #expect(sink.actions.last == .gamepad(.neutral, device))
    try await engine.process(inputs: [.press(.south)], from: device, using: decoded, at: 2)
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test(arguments: [false, true])
  func layerOverrideStopsContinuousOutputAndWaitsForFreshInput(virtual: Bool) async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let original: RemappingDestination = virtual ? .gamepadAxis(.rightStickX) : .mouseMovement(.x)
    let replacement: RemappingDestination =
      virtual ? .gamepadAxis(.rightStickY) : .mouseMovement(.y)
    let profile = RemappingProfile(
      name: "Continuous layer",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [
        RemappingBinding(
          source: .axis(.leftStickX),
          destination: original,
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )
      ],
      layers: [
        RemappingLayer(
          name: "Hold",
          activationMode: .hold,
          activator: .button(.east),
          bindings: [
            RemappingBinding(
              source: .axis(.leftStickX),
              destination: replacement,
              axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
            )
          ]
        )
      ]
    )
    try await engine.process(
      inputs: [.leftStick(x: 0.5, y: 0)],
      from: device,
      using: profile,
      at: 0
    )
    try await engine.tick(at: 1)
    try await engine.process(inputs: [.press(.east)], from: device, using: profile, at: 2)
    let stopped: RemappingEngineAction =
      virtual ? .gamepad(.neutral, device) : .system(.mouseMoved(axis: .x, amount: 0))
    #expect(sink.actions.last == stopped)
    let count = sink.actions.count
    try await engine.tick(at: 3)
    #expect(sink.actions.count == count)
    // Fresh input is a changed stick; an identical snapshot carries no new axis value.
    try await engine.process(
      inputs: [.leftStick(x: 0.25, y: 0)],
      from: device,
      using: profile,
      at: 4
    )
    try await engine.tick(at: 5)
    let resumed: RemappingEngineAction =
      virtual
      ? .gamepad(RemappingGamepadState(axes: [.rightStickY: quantizedStick(0.25)]), device)
      : .system(.mouseMoved(axis: .y, amount: quantizedStick(0.25)))
    #expect(sink.actions.last == resumed)
    try await engine.releaseAll(for: device)
  }

  @Test
  func layerOverrideReleasesHeldVirtualButtonBeforeFreshInput() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(
      name: "Override",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))],
      layers: [
        RemappingLayer(
          name: "Hold",
          activationMode: .hold,
          activator: .button(.east),
          bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.west))]
        )
      ]
    )
    try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 0)
    try await engine.process(inputs: [.press(.east)], from: device, using: profile, at: 1)
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device),
      ]
    )
    try await engine.process(
      inputs: [.release(.south), .press(.south)],
      from: device,
      using: profile,
      at: 2
    )
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [.west]), device))
    try await engine.process(inputs: [.release(.east)], from: device, using: profile, at: 3)
    #expect(sink.actions.last == .gamepad(.neutral, device))
    try await engine.drain()
  }

  @Test(arguments: [false, true])
  func latestLayerWinsAcrossHoldAndToggle(toggleLast: Bool) async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(
      name: "Layers",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [],
      layers: [
        RemappingLayer(
          name: "Hold",
          activationMode: .hold,
          activator: .button(.west),
          bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
        ),
        RemappingLayer(
          name: "Toggle",
          activationMode: .toggle,
          activator: .button(.east),
          bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.east))]
        ),
      ]
    )
    let activators: [InputChange] =
      toggleLast ? [.press(.west), .press(.east)] : [.press(.east), .press(.west)]
    try await engine.process(
      inputs: activators + [.release(.east), .press(.south)],
      from: device,
      using: profile,
      at: 0
    )
    let expected: Control = toggleLast ? .east : .north
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [expected]), device))
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

}
