import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension RemappingMixedOutputTests {
  @Test
  func passthroughConsumesMappedControlsAndPreservesUnmappedControls() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(
      name: "Passthrough",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [
        RemappingBinding(source: .button(.south), destination: .gamepadButton(.north)),
        RemappingBinding(
          source: .axis(.leftStickX),
          destination: .gamepadAxis(.rightStickX),
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        ),
      ]
    )
    try await engine.process(
      inputs: [.press(.east), .press(.south), .leftStick(x: 0.5, y: 0.25)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(
      sink.actions.last
        == .gamepad(
          RemappingGamepadState(
            buttons: [.east, .north],
            axes: [.rightStickX: quantizedStick(0.5), .leftStickY: quantizedStick(0.25)]
          ),
          device
        )
    )
    try await engine.process(inputs: [.release(.south)], from: device, using: profile, at: 1)
    #expect(
      sink.actions.last
        == .gamepad(
          RemappingGamepadState(
            buttons: [.east],
            axes: [.rightStickX: quantizedStick(0.5), .leftStickY: quantizedStick(0.25)]
          ),
          device
        )
    )
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test(arguments: [RemappingAxis.leftStickX, .leftTrigger])
  func analogContributionsAggregateAndRelease(destination: RemappingAxis) async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(
        source: .axis(.leftTrigger),
        destination: .gamepadAxis(destination),
        axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
      ),
      RemappingBinding(
        source: .axis(.rightTrigger),
        destination: .gamepadAxis(destination),
        axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
      ),
    ])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    #expect(
      try RemappingCommandValueParser.destination(
        "gamepad:axis:\(CommandLineName.kebab(destination.rawValue))"
      )
        == .gamepadAxis(destination)
    )
    try await engine.process(
      inputs: [.leftTrigger(0.75), .rightTrigger(0.5)],
      from: device,
      using: decoded,
      at: 0
    )
    let combined = destination == .leftTrigger ? quantizedTrigger(0.75) : 1.0
    #expect(
      sink.actions.last == .gamepad(RemappingGamepadState(axes: [destination: combined]), device)
    )
    try await engine.process(inputs: [.leftTrigger(0)], from: device, using: decoded, at: 1)
    #expect(
      sink.actions.last
        == .gamepad(RemappingGamepadState(axes: [destination: quantizedTrigger(0.5)]), device)
    )
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test
  func opposingDpadBindingsRestoreRemainingHeldDirection() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadDpad(.up)),
      RemappingBinding(source: .button(.east), destination: .gamepadDpad(.down)),
    ])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    #expect(
      try RemappingCommandValueParser.destination("gamepad:dpad:dpad-up") == .gamepadDpad(.up)
    )
    #expect(!profile.requiresSystemInputAccess)
    try await engine.process(inputs: [.press(.south)], from: device, using: decoded, at: 0)
    try await engine.process(inputs: [.press(.east)], from: device, using: decoded, at: 1)
    try await engine.process(inputs: [.release(.east)], from: device, using: decoded, at: 2)
    try await engine.releaseAll(for: device)
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(dpad: [.up]), device), .gamepad(.neutral, device),
        .gamepad(RemappingGamepadState(dpad: [.up]), device), .gamepad(.neutral, device),
      ]
    )
  }

  @Test
  func shutdownWaitsForAsynchronousVirtualSendBeforeNeutralization() async throws {
    let system = MixedOutputRecorder()
    let virtual = SuspendedGamepadSink()
    let engine = RemappingEventEngine(sink: system, gamepadSink: virtual)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    ])
    let sending = Task {
      try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 0)
    }
    await virtual.waitUntilSuspended()
    let shutdown = Task {
      await engine.emissionBarrier.terminate()
      await virtual.markTerminationCompleted()
    }
    await waitUntil("the barrier terminates") { engine.emissionBarrier.isTerminated }
    #expect(await !virtual.terminationCompleted)
    await virtual.resumeSend()
    try await sending.value
    await shutdown.value
    #expect(await virtual.terminationCompleted)
    try await engine.drainAfterTermination()
    #expect(await virtual.states == [RemappingGamepadState(buttons: [.north]), .neutral])
  }

  @Test
  func sequenceTapPreservesBothVirtualTransitions() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(sequences: [
      RemappingSequence(
        sources: [.button(.south), .button(.east)],
        windowMs: 500,
        destination: .gamepadButton(.north)
      )
    ])
    try await engine.process(
      inputs: [.press(.south), .press(.east)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device),
      ]
    )
    try await engine.drain()
    #expect(sink.actions.count == 2)
  }

  @Test
  func failedVirtualPressNeutralizesBothChannelsAndRequiresRecovery() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadButton(.north)),
      RemappingBinding(source: .button(.east), destination: .keyboard(key: .space, modifiers: [])),
    ])
    sink.rejectNextGamepadSend()
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        inputs: [.press(.east), .press(.south)],
        from: device,
        using: profile,
        at: 0
      )
    }
    #expect(
      sink.actions == [
        .system(.keyDown(.space)), .gamepad(RemappingGamepadState(buttons: [.north]), device),
        .system(.keyUp(.space)), .gamepad(.neutral, device),
      ]
    )
    await #expect(throws: RemappingEventEngineError.faulted) {
      try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 1)
    }
    try await engine.recover()
    try await engine.process(inputs: [.press(.south)], from: device, using: profile, at: 2)
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [.north]), device))
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test
  func gamepadDestinationRequiresEnabledOutputPolicy() throws {
    let profile = RemappingProfile(
      name: "Disabled",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))]
    )
    #expect(throws: RemappingValidationError.virtualOutputRequired) { try profile.validate() }
    #expect(
      try RemappingCommandValueParser.destination("gamepad:button:north") == .gamepadButton(.north)
    )
  }

  var device: LogicalControllerID { LogicalControllerID(vendorID: 1, productID: 2, locationID: 1) }

  func makeProfile(
    bindings: [RemappingBinding] = [],
    sequences: [RemappingSequence] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Mixed",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: bindings,
      sequences: sequences
    )
  }
}
