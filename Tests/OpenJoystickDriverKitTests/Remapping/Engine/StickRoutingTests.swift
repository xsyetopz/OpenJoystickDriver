import Testing
@testable import OpenJoystickDriverKit

struct StickRoutingTests {
  @Test func aimSchedulesAndConsumesOnlyMappedStick() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .aim)
    let initial = engine.process(
      events: [.leftStickChanged(x: 1, y: 0), .rightStickChanged(x: 0.5, y: 0)],
      from: device,
      profile: profile,
      at: 0
    )
    #expect(initial == [.gamepad(
      RemappingGamepadState(axes: [.rightStickX: 0.5]), device
    )])
    #expect(engine.nextScheduledTick(
      after: 0, continuousIntervalNanoseconds: 8_000_000
    ) == 8_000_000)
    let movement = engine.tick(at: 10_000_000)
    #expect(movement == [.system(.pointerDelta(x: 1, y: 0))])
    let release = engine.process(
      events: [.leftStickChanged(x: 0, y: 0)],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(release == [.system(.pointerDelta(x: 1, y: 0))])
    #expect(!engine.hasScheduledOutput)
    let idle = engine.tick(at: 30_000_000)
    #expect(idle.isEmpty)
  }

  @Test(arguments: [false, true])
  func flickCancelsOnDisconnectOrProfileReplacement(replaceProfile: Bool) {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .flick)
    let initial = engine.process(
      events: [.leftStickChanged(x: 1, y: 0)],
      from: device,
      profile: profile,
      at: 0
    )
    #expect(initial.isEmpty)
    let centered = engine.process(
      events: [.leftStickChanged(x: 0, y: 0)],
      from: device,
      profile: profile,
      at: 50_000_000
    )
    #expect(centered == [.system(.pointerDelta(x: 45, y: 0))])
    #expect(engine.hasScheduledOutput)
    if replaceProfile {
      _ = engine.setProfile(self.profile(mode: .aim), for: device)
    } else {
      _ = engine.releaseController(device)
    }
    #expect(!engine.hasScheduledOutput)
    let after = engine.tick(at: 100_000_000)
    #expect(after.isEmpty)
  }

  @Test func centeredFlickFinishesWithoutFurtherInput() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = profile(mode: .flickOnly)
    _ = engine.process(
      events: [.leftStickChanged(x: 1, y: 0), .leftStickChanged(x: 0, y: 0)],
      from: device,
      profile: profile,
      at: 0
    )
    let final = engine.tick(at: 100_000_000)
    #expect(final == [.system(.pointerDelta(x: 90, y: 0))])
    #expect(!engine.hasScheduledOutput)
    let repeated = engine.tick(at: 200_000_000)
    #expect(repeated.isEmpty)
  }

  @Test func steeringOwnsOnlyItsVirtualAxisAndReplacementNeutralizesIt() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let steering = RemappingProfile(
      name: "Steering",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      stickMappings: [RemappingStickMapping(
        source: .left,
        mode: .steering,
        tuning: RemappingStickTuning(innerDeadzone: 0),
        rotationDirection: .counterclockwise,
        steeringDegreesAtFullScale: 180,
        steeringReturnDegreesPerSecond: 0,
        steeringOutput: .rightStickX
      )],
      bindings: []
    )
    _ = engine.process(
      events: [.leftStickChanged(x: 1, y: 0)], from: device, profile: steering, at: 0
    )
    #expect(
      engine.process(
        events: [.leftStickChanged(x: 0, y: 1)], from: device, profile: steering, at: 1
      ) == [.gamepad(RemappingGamepadState(axes: [.rightStickX: 0.5]), device)]
    )
    #expect(engine.setProfile(profile(mode: .aim), for: device) == [.gamepad(.neutral, device)])
  }

  private func profile(mode: RemappingStickMode) -> RemappingProfile {
    RemappingProfile(
      name: "Stick routing",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      stickMappings: [RemappingStickMapping(
        source: .left, mode: mode, aimDegreesPerSecond: 100
      )],
      bindings: []
    )
  }
}
