import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingMonotonicTimeTests {
  @Test func backwardTickDoesNotReverseTurboPhase() {
    var state = RemappingEngineState()
    let profile = profile(binding: RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: []),
      turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5)
    ))
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.tick(at: 60_000_000) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 10_000_000).isEmpty)
    #expect(state.nextScheduledTick(after: 10_000_000, continuousIntervalNanoseconds: 1)
      == 100_000_000)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 5_000_000
    ).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test func backwardInputCannotShortenNewPulse() {
    var state = RemappingEngineState()
    let profile = pulseProfile(key: .a)
    _ = state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 100_000_000
    )
    _ = state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 110_000_000
    )
    _ = state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 50_000_000
    )
    #expect(state.tick(at: 200_000_000).isEmpty)
    #expect(state.tick(at: 210_000_000) == [.system(.keyUp(.a))])
  }

  @Test func controllerClocksRemainIndependent() {
    var state = RemappingEngineState()
    let other = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)
    _ = state.process(
      events: [.buttonPressed(.a)],
      from: identifier,
      profile: pulseProfile(key: .a),
      at: 100_000_000
    )
    _ = state.process(
      events: [.buttonPressed(.a)], from: other, profile: pulseProfile(key: .b), at: 0
    )
    #expect(state.tick(at: 100_000_000) == [.system(.keyUp(.b))])
    #expect(state.tick(at: 200_000_000) == [.system(.keyUp(.a))])
  }

  @Test func backwardReleaseStillReleasesHeldOutput() {
    var state = RemappingEngineState()
    let profile = profile(binding: RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .a, modifiers: [])
    ))
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 100)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 0
    ) == [.system(.keyUp(.a))])
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func pulseProfile(key: RemappingKeyboardKey) -> RemappingProfile {
    profile(binding: RemappingBinding(
      source: .button(.south), destination: .keyboard(key: key, modifiers: []), behavior: .pulse
    ))
  }

  private func profile(binding: RemappingBinding) -> RemappingProfile {
    RemappingProfile(
      name: "Monotonic time",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding]
    )
  }
}
