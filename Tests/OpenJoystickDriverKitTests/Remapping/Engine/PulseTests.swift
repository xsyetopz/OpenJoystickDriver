import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingPulseTests {
  @Test func pulseEndsAtItsDeadlineAfterPhysicalRelease() throws {
    var state = RemappingEngineState()
    let profile = profile()
    try profile.validate()
    let identifier = device()
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 10
    ) == [.system(.keyDown(.a))])
    #expect(state.hasScheduledOutput)
    #expect(state.nextScheduledTick(after: 10, continuousIntervalNanoseconds: 1) == 100_000_010)
    #expect(state.tick(at: 100_000_009).isEmpty)
    #expect(state.tick(at: 100_000_010) == [.system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
    #expect(state.nextScheduledTick(after: 100_000_010, continuousIntervalNanoseconds: 1) == nil)
    #expect(state.tick(at: 200_000_000).isEmpty)
  }

  @Test func newPressExtendsPulseAndDrainCancelsItsDeadline() {
    var state = RemappingEngineState()
    let profile = profile()
    let identifier = device()
    _ = state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 0
    )
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 50_000_000
    ).isEmpty)
    #expect(state.tick(at: 100_000_000).isEmpty)
    #expect(state.nextScheduledTick(after: 100_000_000, continuousIntervalNanoseconds: 1)
      == 150_000_000)
    #expect(state.releaseController(identifier) == [.system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
    #expect(state.tick(at: 150_000_000).isEmpty)
  }

  @Test func pulseDeadlineSaturatesWithoutOverflow() {
    var state = RemappingEngineState()
    _ = state.process(
      events: [.buttonPressed(.a)], from: device(), profile: profile(), at: UInt64.max - 10
    )
    #expect(state.nextScheduledTick(after: UInt64.max - 10, continuousIntervalNanoseconds: 1)
      == UInt64.max)
    #expect(state.tick(at: UInt64.max) == [.system(.keyUp(.a))])
  }

  @Test(arguments: [0.0, 5001, Double.infinity, Double.nan])
  func invalidPulseDurationIsRejected(duration: Double) {
    #expect(throws: RemappingValidationError.bindingBehaviorConflict(index: 0)) {
      try profile(duration: duration).validate()
    }
  }

  private func profile(duration: Double = 100) -> RemappingProfile {
    RemappingProfile(
      name: "Pulse",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        behavior: .pulse,
        pulseDurationMs: duration
      )]
    )
  }

  private func device() -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
  }
}
