import Testing

@testable import OpenJoystickDriverKit

struct TriggerRoutingTests {
  @Test
  func exclusiveStagesReleaseSoftBeforePressingFullAndConsumeAnalogInput() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = profile(mode: .exclusive)
    #expect(
      engine.process(inputs: [.leftTrigger(0.2)], from: device, profile: profile, at: 0) == [
        .system(.keyDown(.a))
      ]
    )
    #expect(
      engine.process(inputs: [.leftTrigger(1)], from: device, profile: profile, at: 1) == [
        .system(.keyUp(.a)), .system(.keyDown(.b)),
      ]
    )
    #expect(
      engine.process(inputs: [.leftTrigger(0)], from: device, profile: profile, at: 2) == [
        .system(.keyUp(.b))
      ]
    )
  }

  @Test
  func bufferedSoftPullUsesSharedMonotonicSchedulerAndDisconnectCancelsIt() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = profile(mode: .preferFull)
    #expect(
      engine.process(inputs: [.leftTrigger(0.2)], from: device, profile: profile, at: 10).isEmpty
    )
    #expect(
      engine.nextScheduledTick(after: 10, continuousIntervalNanoseconds: 1_000_000) == 100_000_010
    )
    #expect(engine.tick(at: 100_000_010) == [.system(.keyDown(.a))])
    #expect(engine.releaseController(device) == [.system(.keyUp(.a))])
    #expect(!engine.hasScheduledOutput)

    _ = engine.process(inputs: [.leftTrigger(0.2)], from: device, profile: profile, at: 200_000_000)
    #expect(engine.releaseController(device).isEmpty)
    #expect(!engine.hasScheduledOutput)
  }

  @Test
  func explicitTriggerPassthroughRetainsAnalogVirtualContribution() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = profile(mode: .simultaneous, passthrough: true)
    let actions = engine.process(inputs: [.leftTrigger(0.5)], from: device, profile: profile, at: 0)
    #expect(
      actions == [
        .system(.keyDown(.a)),
        .gamepad(RemappingGamepadState(axes: [.leftTrigger: quantizedTrigger(0.5)]), device),
      ]
    )
  }

  @Test
  func consumedTriggerMappingAlsoWithholdsTriggerClickFromPassthrough() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let actions = engine.process(
      inputs: [.leftTrigger(0.6), .press(.leftTrigger)],
      from: device,
      profile: profile(mode: .simultaneous),
      at: 0
    )
    #expect(actions == [.system(.keyDown(.a))])
  }

  @Test
  func boundTriggerAxisAlsoWithholdsTriggerClickFromPassthrough() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = passthroughProfile(
      binding: RemappingBinding(
        source: .axisDirection(.leftTrigger, .positive),
        destination: .keyboard(key: .a, modifiers: [])
      )
    )
    let actions = engine.process(
      inputs: [.leftTrigger(0.6), .press(.leftTrigger)],
      from: device,
      profile: profile,
      at: 0
    )
    #expect(!actions.contains { if case .gamepad = $0 { true } else { false } })
  }

  @Test
  func boundTriggerClickAlsoWithholdsAnalogTriggerFromPassthrough() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = passthroughProfile(
      binding: RemappingBinding(
        source: .button(.leftTrigger),
        destination: .keyboard(key: .a, modifiers: [])
      )
    )
    let actions = engine.process(
      inputs: [.leftTrigger(0.6), .press(.leftTrigger)],
      from: device,
      profile: profile,
      at: 0
    )
    #expect(actions == [.system(.keyDown(.a))])
  }

  private func passthroughProfile(binding: RemappingBinding) -> RemappingProfile {
    RemappingProfile(
      name: "Trigger passthrough",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [binding]
    )
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
      triggerMappings: [
        RemappingTriggerMapping(
          source: .left,
          mode: mode,
          softThreshold: 0.1,
          fullThreshold: 0.9,
          skipWindowMs: 100,
          passthrough: passthrough
        )
      ],
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
