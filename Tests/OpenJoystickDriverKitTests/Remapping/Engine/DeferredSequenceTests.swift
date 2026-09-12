import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingDeferredSequenceTests {
  @Test func sequenceWaitsForEveryPendingPress() {
    var state = RemappingEngineState()
    let profile = profile()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1
    ).isEmpty)
    #expect(state.devices[identifier]?.deferredSequences.first?.awaitingSources == [.button(.east)])
    #expect(state.process(
      events: [.buttonReleased(.b)], from: identifier, profile: profile, at: 2
    ) == [.system(.keyDown(.d)), .system(.keyUp(.d))])
    #expect(state.tick(at: 600_000_000).isEmpty)
  }

  @Test func consumingLaterGestureDoesNotCancelPreviouslyReplayedDependency() {
    var state = RemappingEngineState()
    let profile = profile()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.x)],
      from: identifier,
      profile: profile,
      at: 1
    ) == [.system(.keyDown(.c))])
    #expect(state.devices[identifier]?.deferredSequences.count == 1)
    #expect(state.tick(at: 500_000_001) == [.system(.keyDown(.d)), .system(.keyUp(.d))])
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile() -> RemappingProfile {
    RemappingProfile(
      name: "Independent chord dependencies",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: [
        RemappingChord(
          sources: [.button(.south), .button(.west)],
          destination: .keyboard(key: .c, modifiers: []),
          mode: .simultaneous,
          windowMs: 500
        ),
        RemappingChord(
          sources: [.button(.east), .button(.north)],
          destination: .keyboard(key: .c, modifiers: []),
          mode: .simultaneous,
          windowMs: 500
        )
      ],
      sequences: [RemappingSequence(
        sources: [.button(.south), .button(.east)],
        windowMs: 200,
        destination: .keyboard(key: .d, modifiers: [])
      )]
    )
  }
}
