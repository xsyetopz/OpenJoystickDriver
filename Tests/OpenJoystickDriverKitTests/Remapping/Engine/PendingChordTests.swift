import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingPendingChordTests {
  @Test func completedChordConsumesBothConstituentActions() {
    var state = RemappingEngineState()
    let profile = profile()
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    #expect(state.nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) == 50_000_001)
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: 50_000_000
    ) == [.system(.keyDown(.c))])
    #expect(!state.hasScheduledOutput)
    #expect(state.process(
      events: [.buttonReleased(.a), .buttonReleased(.b)],
      from: identifier,
      profile: profile,
      at: 60_000_000
    ) == [.system(.keyUp(.c))])
  }

  @Test func timeoutReplaysHeldBindingOnce() {
    var state = RemappingEngineState()
    let profile = profile()
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.tick(at: 50_000_000).isEmpty)
    #expect(state.tick(at: 50_000_001) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 60_000_000).isEmpty)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 70_000_000
    ) == [.system(.keyUp(.a))])
  }

  @Test func earlyReleaseReplaysTapInOrder() {
    var state = RemappingEngineState()
    let profile = profile()
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
  }

  @Test func unmatchedPassthroughTapProducesPressThenNeutral() {
    var state = RemappingEngineState()
    let profile = profile(passthrough: true)
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1
    ) == [
      .gamepad(RemappingGamepadState(buttons: [.south]), identifier), .gamepad(.neutral, identifier)
    ])
  }

  @Test func controllerReleaseCancelsPendingPress() {
    var state = RemappingEngineState()
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile(), at: 0)
    #expect(state.releaseController(identifier).isEmpty)
    #expect(state.tick(at: 100_000_000).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test func completedSmallerChordWaitsForLargerCandidate() {
    var state = RemappingEngineState()
    let profile = overlappingProfile()
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ).isEmpty)
    #expect(state.nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) == 100_000_001)
    #expect(state.tick(at: 50_000_001).isEmpty)
    #expect(state.process(
      events: [.buttonPressed(.y)], from: identifier, profile: profile, at: 75_000_000
    ) == [.system(.keyDown(.d))])
    #expect(!state.hasScheduledOutput)
  }

  @Test func largerCandidateExpiryCommitsCompletedSmallerChord() {
    var state = RemappingEngineState()
    let profile = overlappingProfile()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.tick(at: 100_000_001) == [.system(.keyDown(.c))])
    #expect(!state.hasScheduledOutput)
  }

  @Test func releasingCompletedSmallerChordCommitsItBeforeRelease() {
    var state = RemappingEngineState()
    let profile = overlappingProfile()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 20_000_000
    ) == [.system(.keyDown(.c)), .system(.keyUp(.c))])
    #expect(state.tick(at: 200_000_000).isEmpty)
  }

  @Test func largerChordReleaseDoesNotActivateConsumedSmallerChord() {
    var state = RemappingEngineState()
    let profile = overlappingProfile()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b), .buttonPressed(.y)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonReleased(.y)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyUp(.d))])
    #expect(state.tick(at: 200_000_000).isEmpty)
  }

  @Test func unmatchedDirectionReleaseReplaysItsAxisSample() {
    var state = RemappingEngineState()
    let profile = RemappingProfile(
      name: "Direction replay",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [],
      chords: [RemappingChord(
        sources: [.axisDirection(.leftStickX, .negative), .button(.south)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: .simultaneous
      )]
    )
    #expect(state.process(
      events: [.leftStickChanged(x: -1, y: 0)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    #expect(state.process(
      events: [.leftStickChanged(x: 0, y: 0)], from: identifier, profile: profile, at: 1
    ) == [
      .gamepad(RemappingGamepadState(axes: [.leftStickX: -1]), identifier),
      .gamepad(.neutral, identifier)
    ])
  }

  @Test func modifierChordConsumesBindingsAndSequenceHistory() {
    let sources: [RemappingSource] = [.button(.south), .button(.east)]
    let profile = RemappingProfile(
      name: "Modifier combinations",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: []),
          additionalActions: [RemappingAction(
            destination: .keyboard(key: .x, modifiers: []), behavior: .toggle
          )]
        ),
        RemappingBinding(source: .button(.east), destination: .keyboard(key: .b, modifiers: []))
      ],
      chords: [RemappingChord(
        sources: Set(sources), destination: .keyboard(key: .c, modifiers: [])
      )],
      sequences: [RemappingSequence(
        sources: sources, windowMs: 200, destination: .keyboard(key: .d, modifiers: [])
      )]
    )
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.c))])
    #expect(state.process(
      events: [.buttonReleased(.b), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 1
    ) == [.system(.keyUp(.c))])
  }

  @Test func shorterHigherPriorityWindowDeterminesCommitDeadline() {
    var state = RemappingEngineState()
    let profile = overlappingProfile(smallerWindow: 100, largerWindow: 50)
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ).isEmpty)
    #expect(state.nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) == 50_000_001)
    #expect(state.tick(at: 50_000_001) == [.system(.keyDown(.c))])
    #expect(!state.hasScheduledOutput)
  }

  private func overlappingProfile(
    smallerWindow: Double = 50, largerWindow: Double = 100
  ) -> RemappingProfile {
    let base = profile()
    return RemappingProfile(
      name: base.name,
      device: base.device,
      applicationScope: base.applicationScope,
      bindings: base.bindings,
      chords: [RemappingChord(
        sources: [.button(.south), .button(.east)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: .simultaneous,
        windowMs: smallerWindow
      ), RemappingChord(
        sources: [.button(.south), .button(.east), .button(.north)],
        destination: .keyboard(key: .d, modifiers: []),
        mode: .simultaneous,
        windowMs: largerWindow
      )]
    )
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(passthrough: Bool = false) -> RemappingProfile {
    RemappingProfile(
      name: "Pending chord",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: passthrough ? .passthrough : .disabled),
      bindings: passthrough ? [] : [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: [])),
        RemappingBinding(source: .button(.east), destination: .keyboard(key: .b, modifiers: []))
      ],
      chords: [RemappingChord(
        sources: [.button(.south), .button(.east)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: .simultaneous
      )]
    )
  }
}
