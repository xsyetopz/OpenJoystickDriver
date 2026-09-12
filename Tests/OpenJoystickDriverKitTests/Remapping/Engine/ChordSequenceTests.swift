import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingChordSequenceTests {
  @Test(arguments: [UInt64(0), 10_000_000])
  func replayPreservesPhysicalSequenceOrder(secondPressTime: UInt64) {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    #expect(state.process(
      events: [.buttonPressed(.y)], from: identifier, profile: profile, at: secondPressTime
    ).isEmpty)
    #expect(state.nextScheduledTick(after: secondPressTime, continuousIntervalNanoseconds: 1)
      == 500_000_001)
    #expect(state.tick(at: 500_000_001) == [.system(.keyDown(.d)), .system(.keyUp(.d))])
    #expect(state.tick(at: 600_000_000).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test func delayedReplayDoesNotReverseSequenceOrder() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.north), .button(.south)])
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    _ = state.process(events: [.buttonPressed(.y)], from: identifier, profile: profile, at: 1)
    #expect(state.tick(at: 500_000_001).isEmpty)
  }

  @Test func consumedPressCannotCompleteSequence() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    _ = state.process(events: [.buttonPressed(.y)], from: identifier, profile: profile, at: 1)
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: 2
    ) == [.system(.keyDown(.c))])
    #expect(state.tick(at: 500_000_001).isEmpty)
    #expect(state.releaseController(identifier) == [.system(.keyUp(.c))])
  }

  @Test func originalSequenceWindowStillRejectsSlowInput() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    _ = state.process(
      events: [.buttonPressed(.y)], from: identifier, profile: profile, at: 300_000_000
    )
    #expect(state.tick(at: 500_000_001).isEmpty)
  }

  @Test func unresolvedChordDoesNotAllowUnboundedSequenceHistory() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    for time in 1...100 {
      _ = state.process(
        events: [.buttonPressed(.y), .buttonReleased(.y)],
        from: identifier,
        profile: profile,
        at: UInt64(time)
      )
    }
    #expect(state.devices[identifier]?.sequenceHistory.count == 3)
    #expect(state.devices[identifier]?.pendingChordPresses.count == 1)
    _ = state.releaseController(identifier)
    #expect(!state.hasScheduledOutput)
  }

  @Test func completedPrefixSurvivesLaterUnrelatedInput() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.y), .buttonPressed(.x)],
      from: identifier,
      profile: profile,
      at: 0
    ).isEmpty)
    #expect(state.devices[identifier]?.deferredSequences.count == 1)
    #expect(state.tick(at: 500_000_001) == [.system(.keyDown(.d)), .system(.keyUp(.d))])
    #expect(state.devices[identifier]?.deferredSequences.isEmpty == true)
    #expect(state.tick(at: 600_000_000).isEmpty)
  }

  @Test func chordConsumptionCancelsCompletedPrefixAfterLaterInput() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.y), .buttonPressed(.x)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyDown(.c))])
    #expect(state.devices[identifier]?.deferredSequences.isEmpty == true)
    #expect(state.tick(at: 500_000_001).isEmpty)
  }

  @Test func deferredCompletionDoesNotDuplicateWhileWaiting() {
    var state = RemappingEngineState()
    let profile = profile(sequence: [.button(.south), .button(.north)])
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.y)],
      from: identifier,
      profile: profile,
      at: 0
    )
    for time in 1...100 {
      #expect(state.tick(at: UInt64(time)).isEmpty)
    }
    #expect(state.devices[identifier]?.deferredSequences.count == 1)
    #expect(state.tick(at: 500_000_001) == [.system(.keyDown(.d)), .system(.keyUp(.d))])
  }

  @Test func layerTransitionCancelsDeferredCompletion() {
    var state = RemappingEngineState()
    let profile = profile(
      sequence: [.button(.south), .button(.north)],
      layers: [RemappingLayer(
        name: "Alternate", activationMode: .hold, activator: .button(.leftShoulder)
      )]
    )
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.y)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonPressed(.leftBumper)], from: identifier, profile: profile, at: 1
    ).isEmpty)
    #expect(state.devices[identifier]?.deferredSequences.isEmpty == true)
    #expect(state.tick(at: 500_000_001).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(sequence: [RemappingSource], layers: [RemappingLayer] = [])
    -> RemappingProfile
  {
    RemappingProfile(
      name: "Chord sequence",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: [RemappingChord(
        sources: [.button(.south), .button(.east)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: .simultaneous,
        windowMs: 500
      )],
      sequences: [RemappingSequence(
        sources: sequence, windowMs: 200, destination: .keyboard(key: .d, modifiers: [])
      )],
      layers: layers
    )
  }
}
