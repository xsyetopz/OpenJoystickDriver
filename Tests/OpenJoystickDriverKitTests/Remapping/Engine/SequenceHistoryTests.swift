import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingSequenceHistoryTests {
  @Test(arguments: [false, true])
  func repeatedInputRetainsOnlyBoundedHistory(hasSequence: Bool) {
    var state = RemappingEngineState()
    let profile = profile(hasSequence: hasSequence)
    for time in 0..<1000 {
      _ = state.process(
        events: [.buttonPressed(.a), .buttonReleased(.a)],
        from: identifier,
        profile: profile,
        at: UInt64(time)
      )
    }
    #expect(state.devices[identifier]?.sequenceHistory.count == (hasSequence ? 2 : 0))
    #expect(state.hasScheduledOutput == hasSequence)
  }

  @Test func idleSequenceHistoryExpiresWithoutRepeatedPastDeadlines() {
    var state = RemappingEngineState()
    _ = state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile(), at: 0
    )
    #expect(state.nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) == 100_000_001)
    #expect(state.tick(at: 100_000_000).isEmpty)
    #expect(state.hasScheduledOutput)
    #expect(state.tick(at: 100_000_001).isEmpty)
    #expect(!state.hasScheduledOutput)
    #expect(state.nextScheduledTick(after: 100_000_001, continuousIntervalNanoseconds: 1) == nil)
  }

  @Test func sequenceCanFinishAtInclusiveWindowBoundary() {
    var state = RemappingEngineState()
    _ = state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile(), at: 0
    )
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile(), at: 100_000_000
    ) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
  private let profileID = UUID()

  private func profile(hasSequence: Bool = true) -> RemappingProfile {
    RemappingProfile(
      id: profileID,
      name: "History",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      sequences: hasSequence ? [RemappingSequence(
        id: profileID,
        sources: [.button(.south), .button(.east)],
        windowMs: 100,
        destination: .keyboard(key: .a, modifiers: [])
      )] : []
    )
  }
}
