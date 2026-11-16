import Testing

@testable import OpenJoystickDriverKit

extension GyroRoutingTests {
  @Test
  func layerTuningNeutralizesStickAndResumesAfterFreshBaseline() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(

      name: "Layer sensitivity",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .rightStick, fullStickDegreesPerSecond: 100),
      bindings: [],

      layers: [
        RemappingLayer(
          name: "Aim",
          activationMode: .hold,
          activator: .button(.south),
          motionTuning: RemappingMotionTuning(
            space: .local,
            pitchSensitivity: 0.5,
            yawSensitivity: 0.5,
            automaticBias: false
          )
        )
      ]
    )
    let initial = engine.process(
      inputs: [.motion(sample(0, time: 0)), .motion(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(
      initial == [
        .gamepad(RemappingGamepadState(axes: [.rightStickX: -1, .rightStickY: -0.5]), device)
      ]
    )
    let changed = engine.process(
      inputs: [.press(.south)],
      from: device,
      profile: profile,
      at: 11_000_000
    )
    #expect(changed == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
    let baseline = engine.process(
      inputs: [.motion(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(baseline.isEmpty)
    let resumed = engine.process(
      inputs: [.motion(sample(3, time: 30_000_000))],
      from: device,
      profile: profile,
      at: 30_000_000
    )
    #expect(
      resumed == [
        .gamepad(RemappingGamepadState(axes: [.rightStickX: -0.5, .rightStickY: -0.25]), device)
      ]
    )
    let released = engine.process(
      inputs: [.release(.south)],
      from: device,
      profile: profile,
      at: 31_000_000
    )
    #expect(released == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test
  func trackballMouseRetainsVelocityAndDropsItAcrossSampleGaps() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Trackball",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(
        mode: .mouse,
        trackball: RemappingGyroTrackball(source: .button(.south), decayHalvingsPerSecond: 0)
      ),

      bindings: []
    )
    _ = engine.process(
      inputs: [.motion(sample(0, time: 0)), .motion(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    let held = engine.process(

      inputs: [.press(.south), .motion(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(held == [.system(.pointerDelta(x: -1, y: -0.5))])
    let gap = engine.process(
      inputs: [.motion(sample(3, time: 500_000_000))],
      from: device,
      profile: profile,
      at: 500_000_000
    )
    #expect(gap.isEmpty)
    let after = engine.process(
      inputs: [.motion(sample(4, time: 510_000_000))],
      from: device,
      profile: profile,
      at: 510_000_000
    )
    #expect(after.isEmpty)
  }

  @Test(arguments: [false, true], [RemappingGyroOutputMode.disabled, .mouse])
  func activationConsumptionControlsOriginalVirtualButton(
    consumes: Bool,
    mode: RemappingGyroOutputMode
  ) {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Gyro consumption",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      gyroOutput: RemappingGyroOutput(
        mode: mode,
        activationMode: .whileHeld,
        activationSource: .button(.south),
        consumesActivationSource: consumes
      ),
      bindings: []
    )
    let pressed = engine.process(
      inputs: [.press(.south)],
      from: device,
      profile: profile,
      at: 0
    )
    let suppresses = consumes && mode != .disabled
    let expected: [RemappingEngineAction] =
      suppresses ? [] : [.gamepad(RemappingGamepadState(buttons: [.south]), device)]
    #expect(pressed == expected)
    let released = engine.process(
      inputs: [.release(.south)],
      from: device,
      profile: profile,
      at: 1
    )
    #expect(released == (suppresses ? [] : [.gamepad(.neutral, device)]))
  }

  @Test(arguments: [RemappingGyroActivationMode.whileHeld, .whileReleased, .toggle])
  func activationWaitsForFreshBaselineAndDeactivationClearsStick(mode: RemappingGyroActivationMode)
  {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(

      name: "Gyro activation",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(
        mode: .rightStick,
        fullStickDegreesPerSecond: 100,
        activationMode: mode,

        activationSource: .button(.south)
      ),
      bindings: []
    )
    let initial: [InputChange] = mode == .whileReleased ? [.press(.south)] : []
    _ = engine.process(
      inputs: initial + [.motion(sample(0, time: 0))],
      from: device,
      profile: profile,
      at: 0
    )
    let enable: InputChange = mode == .whileReleased ? .release(.south) : .press(.south)
    let baseline = engine.process(
      inputs: [enable, .motion(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(baseline.isEmpty)
    let movement = engine.process(
      inputs: [.motion(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(!movement.isEmpty)
    let disable: [InputChange] =
      mode == .toggle
      ? [.release(.south), .press(.south)]
      : [mode == .whileHeld ? .release(.south) : .press(.south)]
    let stopped = engine.process(inputs: disable, from: device, profile: profile, at: 21_000_000)
    #expect(stopped == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test
  func gyroTimeoutPreservesOtherBindingsOnSameStick() {
    var engine = RemappingEngineState()
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Combined stick",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .rightStick, fullStickDegreesPerSecond: 100),
      bindings: [
        RemappingBinding(
          source: .axis(.leftStickX),
          destination: .gamepadAxis(.rightStickX),
          axisTuning: RemappingAxisTuning(deadzone: 0)
        )
      ]
    )
    _ = engine.process(
      inputs: [.leftStick(x: 0.25, y: 0), .motion(sample(0, time: 0))],
      from: device,
      profile: profile,
      at: 0
    )
    let combined = engine.process(
      inputs: [.motion(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(
      combined == [
        .gamepad(
          RemappingGamepadState(axes: [
            .rightStickX: -1 + quantizedStick(0.25), .rightStickY: -0.5,
          ]),
          device
        )
      ]
    )
    let expired = engine.tick(at: 110_000_000)
    #expect(
      expired == [
        .gamepad(RemappingGamepadState(axes: [.rightStickX: quantizedStick(0.25)]), device)
      ]
    )
    let released = engine.releaseController(device)
    #expect(released == [.gamepad(.neutral, device)])
  }

  @Test(arguments: [false, true])
  func calibrationResetImmediatelyNeutralizesGyroStick(rejectReset: Bool) async throws {
    let virtual = GyroResetGamepadSink()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), gamepadSink: virtual)
    let device = LogicalControllerID(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Gyro reset",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .leftStick, fullStickDegreesPerSecond: 100),
      bindings: []
    )
    try await engine.process(
      inputs: [.motion(sample(0, time: 0)), .motion(sample(1, time: 10_000_000))],
      from: device,
      using: profile,
      at: 10_000_000
    )
    #expect(await engine.hasScheduledOutput())
    if rejectReset {
      await virtual.rejectNextSend()
      await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
        try await engine.calibrateMotion(.reset, for: device)
      }
      #expect(await engine.motionCalibrationStatus(for: device) == nil)
      #expect(await virtual.states.last == .neutral)
      await #expect(throws: RemappingEventEngineError.faulted) {
        try await engine.tick(at: 20_000_000)
      }
      try await engine.recover()
      #expect(await !engine.hasScheduledOutput())
      return
    }
    let reset = try await engine.calibrateMotion(.reset, for: device)
    #expect(!reset.hasMotionBaseline)
    #expect(
      await virtual.states == [
        RemappingGamepadState(axes: [.leftStickX: -1, .leftStickY: -0.5]), .neutral,
      ]
    )
    #expect(await !engine.hasScheduledOutput())
  }

}
