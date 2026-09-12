import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingExplicitReleaseTests {
  @Test func explicitPressSurvivesPhysicalReleaseUntilReleaseAction() throws {
    var state = RemappingEngineState()
    let profile = profile()
    try profile.validate()
    let device = identifier(1)
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.a))])
    #expect(!state.hasScheduledOutput)
    #expect(state.process(
      events: [.buttonPressed(.b), .buttonReleased(.b)],
      from: device,
      profile: profile,
      at: 1
    ) == [.system(.keyUp(.a))])
    #expect(state.drain().isEmpty)
  }

  @Test func explicitReleasePreservesAnotherControllersReference() {
    var state = RemappingEngineState()
    let profile = profile()
    for location: UInt32 in [1, 2] {
      _ = state.process(
        events: [.buttonPressed(.a)], from: identifier(location), profile: profile, at: 0
      )
    }
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier(1), profile: profile, at: 1
    ).isEmpty)
    #expect(state.releaseController(identifier(2)) == [.system(.keyUp(.a))])
  }

  @Test func explicitReleaseCancelsPulseDeadline() {
    var state = RemappingEngineState()
    let profile = profile(behavior: .pulse)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier(1), profile: profile, at: 0)
    #expect(state.hasScheduledOutput)
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier(1), profile: profile, at: 1
    ) == [.system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
    #expect(state.tick(at: 100_000_000).isEmpty)
  }

  private func identifier(_ location: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: location)
  }

  private func profile(behavior: RemappingBindingBehavior = .press) -> RemappingProfile {
    RemappingProfile(
      name: "Explicit release",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: []),
          behavior: behavior
        ),
        RemappingBinding(
          source: .button(.east), destination: .keyboard(key: .a, modifiers: []), behavior: .release
        )
      ]
    )
  }
}
