import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingActivationSchedulingTests {
  @Test(arguments: [false, true])
  func expiredTapDoesNotCombineWithNextPress(tickBeforePress: Bool) {
    var state = RemappingEngineState()
    let profile = profile(multiTap: true)
    _ = state.process(
      inputs: [.press(.south), .release(.south)],
      from: identifier,
      profile: profile,
      at: 0
    )
    var actions: [RemappingEngineAction] = []
    if tickBeforePress { actions += state.tick(at: 200_000_000) }
    actions += state.process(
      inputs: [.press(.south)],
      from: identifier,
      profile: profile,
      at: 200_000_000
    )
    #expect(actions == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    _ = state.process(
      inputs: [.release(.south)],
      from: identifier,
      profile: profile,
      at: 200_000_001
    )
    #expect(state.tick(at: 400_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test
  func completedMultiTapDoesNotCombineWithThirdPress() {
    var state = RemappingEngineState()
    let profile = profile(multiTap: true)
    #expect(
      state.process(
        inputs: [
          .press(.south), .release(.south), .press(.south), .release(.south),
        ],
        from: identifier,
        profile: profile,
        at: 0
      ) == [.system(.keyDown(.b)), .system(.keyUp(.b))]
    )
    #expect(
      state.process(
        inputs: [.press(.south), .release(.south)],
        from: identifier,
        profile: profile,
        at: 1
      ).isEmpty
    )
    #expect(state.tick(at: 200_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test
  func earlyLongHoldReleaseLeavesNoScheduledWork() {
    var state = RemappingEngineState()
    let profile = profile(multiTap: false)
    _ = state.process(inputs: [.press(.south)], from: identifier, profile: profile, at: 0)
    #expect(state.hasScheduledOutput)
    #expect(
      state.process(inputs: [.release(.south)], from: identifier, profile: profile, at: 1) == [
        .system(.keyDown(.a)), .system(.keyUp(.a)),
      ]
    )
    #expect(!state.hasScheduledOutput)
    #expect(state.tick(at: 500_000_000).isEmpty)
  }

  @Test
  func multiTapSchedulesOnlyAfterReleaseAndStopsAfterExpiry() {
    var state = RemappingEngineState()
    let profile = profile(multiTap: true)
    _ = state.process(inputs: [.press(.south)], from: identifier, profile: profile, at: 0)
    #expect(!state.hasScheduledOutput)
    _ = state.process(inputs: [.release(.south)], from: identifier, profile: profile, at: 1)
    #expect(state.hasScheduledOutput)
    #expect(state.tick(at: 200_000_001) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func firedLongHoldDoesNotScheduleWhileOutputIsHeld() {
    var state = RemappingEngineState()
    let profile = profile(multiTap: false)
    _ = state.process(inputs: [.press(.south)], from: identifier, profile: profile, at: 0)
    #expect(state.tick(at: 500_000_000) == [.system(.keyDown(.b))])
    #expect(!state.hasScheduledOutput)
    #expect(
      state.process(
        inputs: [.release(.south)],
        from: identifier,
        profile: profile,
        at: 500_000_001
      ) == [.system(.keyUp(.b))]
    )
    #expect(!state.hasScheduledOutput)
  }

  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  private func profile(multiTap: Bool) -> RemappingProfile {
    let alternate = RemappingDestination.keyboard(key: .b, modifiers: [])
    return RemappingProfile(
      name: "Activation scheduling",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: []),
          longHold: multiTap ? nil : RemappingLongHold(durationMs: 500, destination: alternate),
          multiTap: multiTap
            ? [RemappingMultiTap(count: 2, windowMs: 200, destination: alternate)] : []
        )
      ]
    )
  }
}
