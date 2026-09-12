import Testing

@testable import OpenJoystickDriverKit

struct TriggerRoutingTests {
  @Test func exclusiveStagesReleaseSoftBeforePressingFullAndConsumeAnalogInput() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .exclusive)
    #expect(
      engine.process(
        events: [.leftTriggerChanged(0.2)], from: device, profile: profile, at: 0
      ) == [.system(.keyDown(.a))]
    )
    #expect(
      engine.process(
        events: [.leftTriggerChanged(1)], from: device, profile: profile, at: 1
      ) == [.system(.keyUp(.a)), .system(.keyDown(.b))]
    )
    #expect(
      engine.process(
        events: [.leftTriggerChanged(0)], from: device, profile: profile, at: 2
      ) == [.system(.keyUp(.b))]
    )
  }

  @Test func bufferedSoftPullUsesTheSharedMonotonicSchedulerAndDisconnectCancelsIt() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .preferFull)
    #expect(
      engine.process(
        events: [.leftTriggerChanged(0.2)], from: device, profile: profile, at: 10
      ).isEmpty
    )
    #expect(
      engine.nextScheduledTick(after: 10, continuousIntervalNanoseconds: 1_000_000)
        == 100_000_010
    )
    #expect(engine.tick(at: 100_000_010) == [.system(.keyDown(.a))])
    #expect(engine.releaseController(device) == [.system(.keyUp(.a))])
    #expect(!engine.hasScheduledOutput)

    _ = engine.process(
      events: [.leftTriggerChanged(0.2)], from: device, profile: profile, at: 200_000_000
    )
    #expect(engine.releaseController(device).isEmpty)
    #expect(!engine.hasScheduledOutput)
  }

  @Test func explicitTriggerPassthroughRetainsTheAnalogVirtualContribution() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .simultaneous, passthrough: true)
    let actions = engine.process(
      events: [.leftTriggerChanged(0.5)], from: device, profile: profile, at: 0
    )
    #expect(actions == [
      .system(.keyDown(.a)),
      .gamepad(RemappingGamepadState(axes: [.leftTrigger: 0.5]), device),
    ])
  }

  private func profile(
    mode: RemappingDualStageTriggerMode,
    passthrough: Bool = false
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Trigger routing",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      triggerMappings: [RemappingTriggerMapping(
        source: .left,
        mode: mode,
        softThreshold: 0.1,
        fullThreshold: 0.9,
        skipWindowMs: 100,
        passthrough: passthrough
      )],
      bindings: [
        RemappingBinding(
          source: .triggerStage(.left, .soft),
          destination: .keyboard(key: .a, modifiers: [])
        ),
        RemappingBinding(
          source: .triggerStage(.left, .full),
          destination: .keyboard(key: .b, modifiers: [])
        ),
      ]
    )
  }
}
