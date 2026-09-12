import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingMixedOutputTests {
  @Test(arguments: [RemappingBindingBehavior.tapOnPress, .tapOnRelease])
  func edgeTapFiresOnceAndDoesNotLeaveHeldOutput(behavior: RemappingBindingBehavior) async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [RemappingBinding(
      source: .button(.south), destination: .gamepadButton(.north), behavior: behavior
    )])
    try await engine.process(
      events: [.buttonReleased(.a)], from: device, using: profile, at: 0
    )
    #expect(sink.actions.isEmpty)
    try await engine.process(
      events: [.buttonPressed(.a), .buttonPressed(.a)], from: device, using: profile, at: 1
    )
    #expect(sink.actions.count == (behavior == .tapOnPress ? 2 : 0))
    try await engine.process(
      events: [.buttonReleased(.a), .buttonReleased(.a)], from: device, using: profile, at: 2
    )
    #expect(sink.actions == [
      .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device)
    ])
    try await engine.releaseAll(for: device)
    #expect(sink.actions.count == 2)
  }

  @Test func lifecycleCancellationDoesNotFireAnArmedReleaseTap() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [RemappingBinding(
      source: .button(.south), destination: .gamepadButton(.north), behavior: .tapOnRelease
    )])
    try await engine.process(events: [.buttonPressed(.a)], from: device, using: profile, at: 0)
    try await engine.releaseAll(for: device)
    try await engine.process(events: [.buttonReleased(.a)], from: device, using: profile, at: 1)
    #expect(sink.actions.isEmpty)
  }

  @Test func layerOverrideCancelsReleaseTapEvenWhenOriginalLayerReturns() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(
      name: "Release cancellation",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(
        source: .button(.south), destination: .gamepadButton(.north), behavior: .tapOnRelease
      )],
      layers: [RemappingLayer(
        name: "Override",
        activationMode: .hold,
        activator: .button(.east),
        bindings: [RemappingBinding(
          source: .button(.south), destination: .gamepadButton(.west), behavior: .tapOnRelease
        )]
      )]
    )
    try await engine.process(
      events: [
        .buttonPressed(.a), .buttonPressed(.b), .buttonReleased(.b), .buttonReleased(.a)
      ],
      from: device,
      using: profile,
      at: 0
    )
    #expect(sink.actions.isEmpty)
    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)], from: device, using: profile, at: 1
    )
    #expect(sink.actions == [
      .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device)
    ])
  }

  @Test func toggleInputCanCompleteASequenceWithoutLosingItsHeldOutput() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(
      bindings: [RemappingBinding(
        source: .button(.south), destination: .gamepadButton(.north), behavior: .toggle
      )],
      sequences: [RemappingSequence(
        sources: [.button(.west), .button(.south)],
        windowMs: 500,
        destination: .gamepadButton(.east)
      )]
    )
    try await engine.process(
      events: [.buttonPressed(.x), .buttonReleased(.x), .buttonPressed(.a)],
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

  @Test func togglePersistsThroughReleaseAndDrainsOnLifecycleChange() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [RemappingBinding(
      source: .button(.south), destination: .gamepadButton(.north), behavior: .toggle
    )])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device,
      using: decoded,
      at: 0
    )
    #expect(sink.actions == [.gamepad(RemappingGamepadState(buttons: [.north]), device)])
    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device,
      using: decoded,
      at: 1
    )
    #expect(sink.actions.last == .gamepad(.neutral, device))
    try await engine.process(events: [.buttonPressed(.a)], from: device, using: decoded, at: 2)
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
      bindings: [RemappingBinding(
        source: .axis(.leftStickX),
        destination: original,
        axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
      )],
      layers: [RemappingLayer(
        name: "Hold",
        activationMode: .hold,
        activator: .button(.east),
        bindings: [RemappingBinding(
          source: .axis(.leftStickX),
          destination: replacement,
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )]
      )]
    )
    try await engine.process(
      events: [.leftStickChanged(x: 0.5, y: 0)],
      from: device,
      using: profile,
      at: 0
    )
    try await engine.tick(at: 1)
    try await engine.process(events: [.buttonPressed(.b)], from: device, using: profile, at: 2)
    let stopped: RemappingEngineAction = virtual
      ? .gamepad(.neutral, device) : .system(.mouseMoved(axis: .x, amount: 0))
    #expect(sink.actions.last == stopped)
    let count = sink.actions.count
    try await engine.tick(at: 3)
    #expect(sink.actions.count == count)
    try await engine.process(
      events: [.leftStickChanged(x: 0.5, y: 0)],
      from: device,
      using: profile,
      at: 4
    )
    try await engine.tick(at: 5)
    let resumed: RemappingEngineAction = virtual
      ? .gamepad(RemappingGamepadState(axes: [.rightStickY: 0.5]), device)
      : .system(.mouseMoved(axis: .y, amount: 0.5))
    #expect(sink.actions.last == resumed)
    try await engine.releaseAll(for: device)
  }

  @Test func layerOverrideReleasesHeldVirtualButtonBeforeFreshInput() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = RemappingProfile(
      name: "Override",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))],
      layers: [RemappingLayer(
        name: "Hold",
        activationMode: .hold,
        activator: .button(.east),
        bindings: [RemappingBinding(source: .button(.south), destination: .gamepadButton(.west))]
      )]
    )
    try await engine.process(events: [.buttonPressed(.a)], from: device, using: profile, at: 0)
    try await engine.process(events: [.buttonPressed(.b)], from: device, using: profile, at: 1)
    #expect(sink.actions == [
      .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device)
    ])
    try await engine.process(
      events: [.buttonReleased(.a), .buttonPressed(.a)],
      from: device,
      using: profile,
      at: 2
    )
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [.west]), device))
    try await engine.process(events: [.buttonReleased(.b)], from: device, using: profile, at: 3)
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
        )
      ]
    )
    let activators: [ControllerEvent] = toggleLast
      ? [.buttonPressed(.x), .buttonPressed(.b)] : [.buttonPressed(.b), .buttonPressed(.x)]
    try await engine.process(
      events: activators + [.buttonReleased(.b), .buttonPressed(.a)],
      from: device,
      using: profile,
      at: 0
    )
    let expected: RemappingButton = toggleLast ? .east : .north
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [expected]), device))
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test func passthroughConsumesMappedControlsAndPreservesUnmappedControls() async throws {
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
        )
      ]
    )
    try await engine.process(
      events: [.buttonPressed(.b), .buttonPressed(.a), .leftStickChanged(x: 0.5, y: 0.25)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(sink.actions.last == .gamepad(
      RemappingGamepadState(buttons: [.east, .north], axes: [.rightStickX: 0.5, .leftStickY: 0.25]),
      device
    ))
    try await engine.process(events: [.buttonReleased(.a)], from: device, using: profile, at: 1)
    #expect(sink.actions.last == .gamepad(
      RemappingGamepadState(buttons: [.east], axes: [.rightStickX: 0.5, .leftStickY: 0.25]), device
    ))
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
      )
    ])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    #expect(
      try RemappingCommandValueParser.destination("gamepad:axis:\(destination.rawValue)")
        == .gamepadAxis(destination)
    )
    try await engine.process(
      events: [.leftTriggerChanged(0.75), .rightTriggerChanged(0.5)],
      from: device,
      using: decoded,
      at: 0
    )
    let combined = destination == .leftTrigger ? 0.75 : 1.0
    #expect(
      sink.actions.last == .gamepad(RemappingGamepadState(axes: [destination: combined]), device)
    )
    try await engine.process(events: [.leftTriggerChanged(0)], from: device, using: decoded, at: 1)
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(axes: [destination: 0.5]), device))
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test func opposingDpadBindingsRestoreTheRemainingHeldDirection() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadDpad(.up)),
      RemappingBinding(source: .button(.east), destination: .gamepadDpad(.down))
    ])
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
    #expect(try RemappingCommandValueParser.destination("gamepad:dpad:up") == .gamepadDpad(.up))
    #expect(!profile.requiresSystemInputAccess)
    try await engine.process(events: [.buttonPressed(.a)], from: device, using: decoded, at: 0)
    try await engine.process(events: [.buttonPressed(.b)], from: device, using: decoded, at: 1)
    try await engine.process(events: [.buttonReleased(.b)], from: device, using: decoded, at: 2)
    try await engine.releaseAll(for: device)
    #expect(sink.actions == [
      .gamepad(RemappingGamepadState(dpad: [.up]), device), .gamepad(.neutral, device),
      .gamepad(RemappingGamepadState(dpad: [.up]), device), .gamepad(.neutral, device)
    ])
  }

  @Test func shutdownWaitsForAnAsynchronousVirtualSendBeforeNeutralization() async throws {
    let system = MixedOutputRecorder()
    let virtual = SuspendedGamepadSink()
    let engine = RemappingEventEngine(sink: system, gamepadSink: virtual)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    ])
    let sending = Task {
      try await engine.process(events: [.buttonPressed(.a)], from: device, using: profile, at: 0)
    }
    await virtual.waitUntilSuspended()
    let shutdown = Task {
      await engine.emissionBarrier.terminate()
      await virtual.markTerminationCompleted()
    }
    while !engine.emissionBarrier.isTerminated { await Task.yield() }
    #expect(await !virtual.terminationCompleted)
    await virtual.resumeSend()
    try await sending.value
    await shutdown.value
    #expect(await virtual.terminationCompleted)
    try await engine.drainAfterTermination()
    #expect(await virtual.states == [RemappingGamepadState(buttons: [.north]), .neutral])
  }

  @Test func sequenceTapPreservesBothVirtualTransitions() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(
      sequences: [
        RemappingSequence(
          sources: [.button(.south), .button(.east)],
          windowMs: 500,
          destination: .gamepadButton(.north)
        )
      ]
    )
    try await engine.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(
      sink.actions == [
        .gamepad(RemappingGamepadState(buttons: [.north]), device), .gamepad(.neutral, device)
      ]
    )
    try await engine.drain()
    #expect(sink.actions.count == 2)
  }

  @Test func failedVirtualPressNeutralizesBothChannelsAndRequiresRecovery() async throws {
    let sink = MixedOutputRecorder()
    let engine = RemappingEventEngine(sink: sink, gamepadSink: sink)
    let profile = makeProfile(bindings: [
      RemappingBinding(source: .button(.south), destination: .gamepadButton(.north)),
      RemappingBinding(source: .button(.east), destination: .keyboard(key: .space, modifiers: []))
    ])
    sink.rejectNextGamepadSend()
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        events: [.buttonPressed(.b), .buttonPressed(.a)],
        from: device,
        using: profile,
        at: 0
      )
    }
    #expect(
      sink.actions == [
        .system(.keyDown(.space)), .gamepad(RemappingGamepadState(buttons: [.north]), device),
        .system(.keyUp(.space)), .gamepad(.neutral, device)
      ]
    )
    await #expect(throws: RemappingEventEngineError.faulted) {
      try await engine.process(events: [.buttonPressed(.a)], from: device, using: profile, at: 1)
    }
    try await engine.recover()
    try await engine.process(events: [.buttonPressed(.a)], from: device, using: profile, at: 2)
    #expect(sink.actions.last == .gamepad(RemappingGamepadState(buttons: [.north]), device))
    try await engine.releaseAll(for: device)
    #expect(sink.actions.last == .gamepad(.neutral, device))
  }

  @Test func gamepadDestinationRequiresAnEnabledOutputPolicy() throws {
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

  private var device: DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
  }

  private func makeProfile(
    bindings: [RemappingBinding] = [], sequences: [RemappingSequence] = []
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

private final class MixedOutputRecorder: RemappingSystemInputSink, RemappingGamepadSink,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recorded: [RemappingEngineAction] = []
  private var rejectsNextGamepad = false

  var actions: [RemappingEngineAction] { lock.withLock { recorded } }

  func rejectNextGamepadSend() { lock.withLock { rejectsNextGamepad = true } }

  func send(_ action: RemappingSystemInputAction) {
    lock.withLock { recorded.append(.system(action)) }
  }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
    let reject = lock.withLock {
      recorded.append(.gamepad(state, identifier))
      defer { rejectsNextGamepad = false }
      return rejectsNextGamepad
    }
    if reject { throw RemappingEventEngineError.sinkUnavailable }
    await Task.yield()
  }
}

private actor SuspendedGamepadSink: RemappingGamepadSink {
  private(set) var states: [RemappingGamepadState] = []
  private(set) var terminationCompleted = false
  private var suspended = false
  private var startedWaiter: CheckedContinuation<Void, Never>?
  private var sendWaiter: CheckedContinuation<Void, Never>?

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async {
    states.append(state)
    guard !suspended else { return }
    suspended = true
    startedWaiter?.resume()
    startedWaiter = nil
    await withCheckedContinuation { sendWaiter = $0 }
  }

  func waitUntilSuspended() async {
    guard !suspended else { return }
    await withCheckedContinuation { startedWaiter = $0 }
  }

  func resumeSend() {
    sendWaiter?.resume()
    sendWaiter = nil
  }

  func markTerminationCompleted() { terminationCompleted = true }
}
