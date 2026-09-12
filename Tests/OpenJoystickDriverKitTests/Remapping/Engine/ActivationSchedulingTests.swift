import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingActivationSchedulingTests {
  @Test(arguments: [false, true])
  func expiredTapDoesNotCombineWithNextPress(tickBeforePress: Bool) {
    var state = RemappingEngineState()
    let profile = profile(doubleTap: true)
    _ = state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 0
    )
    var actions: [RemappingEngineAction] = []
    if tickBeforePress { actions += state.tick(at: 200_000_000) }
    actions += state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 200_000_000
    )
    #expect(actions == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    _ = state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 200_000_001
    )
    #expect(state.tick(at: 400_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test func completedDoubleTapDoesNotCombineWithThirdPress() {
    var state = RemappingEngineState()
    let profile = profile(doubleTap: true)
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a), .buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.b)), .system(.keyUp(.b))])
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      profile: profile,
      at: 1
    ).isEmpty)
    #expect(state.tick(at: 200_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test func earlyLongHoldReleaseLeavesNoScheduledWork() {
    var state = RemappingEngineState()
    let profile = profile(doubleTap: false)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.hasScheduledOutput)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
    #expect(state.tick(at: 500_000_000).isEmpty)
  }

  @Test func doubleTapSchedulesOnlyAfterReleaseAndStopsAfterExpiry() {
    var state = RemappingEngineState()
    let profile = profile(doubleTap: true)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(!state.hasScheduledOutput)
    _ = state.process(events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 1)
    #expect(state.hasScheduledOutput)
    #expect(state.tick(at: 200_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
  }

  @Test func firedLongHoldDoesNotScheduleWhileOutputIsHeld() {
    var state = RemappingEngineState()
    let profile = profile(doubleTap: false)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.tick(at: 500_000_000) == [.system(.keyDown(.b))])
    #expect(!state.hasScheduledOutput)
    #expect(state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 500_000_001
    ) == [.system(.keyUp(.b))])
    #expect(!state.hasScheduledOutput)
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(doubleTap: Bool) -> RemappingProfile {
    let alternate = RemappingDestination.keyboard(key: .b, modifiers: [])
    return RemappingProfile(
      name: "Activation scheduling",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        longHold: doubleTap ? nil : RemappingLongHold(durationMs: 500, destination: alternate),
        doubleTap: doubleTap ? RemappingDoubleTap(windowMs: 200, destination: alternate) : nil
      )]
    )
  }
}
