import Testing

@testable import OpenJoystickDriverKit

struct RemappingFailureTests {
  @Test func successfulKeyReleaseIsNotRepeatedWhenLaterModifierReleaseFails() async throws {
    let sink = RemappingTestSink(failingCalls: [4])
    let engine = RemappingEventEngine(sink: sink)
    let profile = chordProfile()
    let identifier = device()

    try await engine.process(events: [.buttonPressed(.a)], from: identifier, using: profile, at: 0)
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) { try await engine.drain() }

    #expect(
      sink.actions() == [.modifierDown(.shift), .keyDown(.a), .keyUp(.a), .modifierUp(.shift)]
    )
  }

  @Test func earlierNeutralOutputIsNotReleasedAfterALaterActionFails() async throws {
    let sink = RemappingTestSink(failingCalls: [3])
    let engine = RemappingEventEngine(sink: sink)
    let profile = RemappingProfile(
      name: "Partial batch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: [])),
        RemappingBinding(source: .button(.east), destination: .keyboard(key: .b, modifiers: []))
      ]
    )

    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        events: [.buttonPressed(.a), .buttonReleased(.a), .buttonPressed(.b)],
        from: device(),
        using: profile,
        at: 0
      )
    }

    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a), .keyUp(.b)])
  }

  @Test func failedPressIsConservativelyReleased() async throws {
    let sink = RemappingTestSink(failingCalls: [1])
    let engine = RemappingEventEngine(sink: sink)
    let profile = RemappingProfile(
      name: "Failed press",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ]
    )

    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(events: [.buttonPressed(.a)], from: device(), using: profile, at: 0)
    }

    #expect(sink.actions() == [.keyUp(.a)])
  }

  @Test func recoveryRetriesOnlyTheExactRemainingOutput() async throws {
    let sink = RemappingTestSink(failingCalls: [4, 5])
    let engine = RemappingEventEngine(sink: sink)

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(),
      using: chordProfile(),
      at: 0
    )
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) { try await engine.drain() }
    try await engine.recover()

    #expect(
      sink.actions() == [.modifierDown(.shift), .keyDown(.a), .keyUp(.a), .modifierUp(.shift)]
    )
  }

  @Test func terminalDrainRetriesOnlyTheExactRemainingOutput() async throws {
    let sink = RemappingTestSink(failingCalls: [4, 5])
    let barrier = RemappingEmissionBarrier()
    let engine = RemappingEventEngine(sink: sink, emissionBarrier: barrier)

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(),
      using: chordProfile(),
      at: 0
    )
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) { try await engine.drain() }

    await barrier.terminate()
    try await engine.drainAfterTermination()

    #expect(
      sink.actions() == [.modifierDown(.shift), .keyDown(.a), .keyUp(.a), .modifierUp(.shift)]
    )
  }

  @Test func sinkFailureNeutralizesPotentialOutputsAndFaultsUntilRecovery() async throws {
    let sink = RemappingTestSink(failingCalls: [2, 3])
    let engine = RemappingEventEngine(sink: sink)
    let profile = RemappingProfile(
      name: "Failure",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: [.shift])
        )
      ]
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        events: [.buttonPressed(.a)],
        from: identifier,
        using: profile,
        at: 0
      )
    }
    await #expect(throws: RemappingEventEngineError.faulted) {
      try await engine.process(
        events: [.buttonPressed(.a)],
        from: identifier,
        using: profile,
        at: 1
      )
    }

    try await engine.recover()
    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      using: profile,
      at: 2
    )

    #expect(
      sink.actions() == [
        .modifierDown(.shift), .keyUp(.a), .modifierUp(.shift), .modifierDown(.shift), .keyDown(.a),
        .keyUp(.a), .modifierUp(.shift)
      ]
    )
  }

  private func chordProfile() -> RemappingProfile {
    RemappingProfile(
      name: "Failure",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: [.shift])
        )
      ]
    )
  }

  private func device() -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
  }
}
