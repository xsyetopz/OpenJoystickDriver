import Testing

@testable import OpenJoystickDriverKit

struct GyroRoutingTests {
  @Test func layerTuningNeutralizesStickAndResumesAfterFreshBaseline() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Layer sensitivity",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .rightStick, fullStickDegreesPerSecond: 100),
      bindings: [],
      layers: [RemappingLayer(
        name: "Aim",
        activationMode: .hold,
        activator: .button(.south),
        motionTuning: RemappingMotionTuning(
          space: .local, pitchSensitivity: 0.5, yawSensitivity: 0.5, automaticBias: false
        )
      )]
    )
    let initial = engine.process(
      events: [.motionSample(sample(0, time: 0)), .motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(initial == [.gamepad(
      RemappingGamepadState(axes: [.rightStickX: -1, .rightStickY: 0.5]), device
    )])
    let changed = engine.process(
      events: [.buttonPressed(.a)], from: device, profile: profile, at: 11_000_000
    )
    #expect(changed == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
    let baseline = engine.process(
      events: [.motionSample(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(baseline.isEmpty)
    let resumed = engine.process(
      events: [.motionSample(sample(3, time: 30_000_000))],
      from: device,
      profile: profile,
      at: 30_000_000
    )
    #expect(resumed == [.gamepad(
      RemappingGamepadState(axes: [.rightStickX: -0.5, .rightStickY: 0.25]), device
    )])
    let released = engine.process(
      events: [.buttonReleased(.a)], from: device, profile: profile, at: 31_000_000
    )
    #expect(released == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test func trackballMouseRetainsVelocityAndDropsItAcrossSampleGaps() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
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
      events: [.motionSample(sample(0, time: 0)), .motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    let held = engine.process(
      events: [.buttonPressed(.a), .motionSample(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(held == [.system(.pointerDelta(x: -1, y: -0.5))])
    let gap = engine.process(
      events: [.motionSample(sample(3, time: 500_000_000))],
      from: device,
      profile: profile,
      at: 500_000_000
    )
    #expect(gap.isEmpty)
    let after = engine.process(
      events: [.motionSample(sample(4, time: 510_000_000))],
      from: device,
      profile: profile,
      at: 510_000_000
    )
    #expect(after.isEmpty)
  }

  @Test(arguments: [false, true], [RemappingGyroOutputMode.disabled, .mouse])
  func activationConsumptionControlsOriginalVirtualButton(
    consumes: Bool, mode: RemappingGyroOutputMode
  ) {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
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
      events: [.buttonPressed(.a)], from: device, profile: profile, at: 0
    )
    let suppresses = consumes && mode != .disabled
    let expected: [RemappingEngineAction] = suppresses ? [] : [
      .gamepad(RemappingGamepadState(buttons: [.south]), device)
    ]
    #expect(pressed == expected)
    let released = engine.process(
      events: [.buttonReleased(.a)], from: device, profile: profile, at: 1
    )
    #expect(released == (suppresses ? [] : [.gamepad(.neutral, device)]))
  }

  @Test(arguments: [RemappingGyroActivationMode.whileHeld, .whileReleased, .toggle])
  func activationWaitsForFreshBaselineAndDeactivationClearsStick(
    mode: RemappingGyroActivationMode
  ) {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
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
    let initial: [ControllerEvent] = mode == .whileReleased ? [.buttonPressed(.a)] : []
    _ = engine.process(
      events: initial + [.motionSample(sample(0, time: 0))],
      from: device,
      profile: profile,
      at: 0
    )
    let enable: ControllerEvent = mode == .whileReleased ? .buttonReleased(.a) : .buttonPressed(.a)
    let baseline = engine.process(
      events: [enable, .motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(baseline.isEmpty)
    let movement = engine.process(
      events: [.motionSample(sample(2, time: 20_000_000))],
      from: device,
      profile: profile,
      at: 20_000_000
    )
    #expect(!movement.isEmpty)
    let disable: [ControllerEvent] = mode == .toggle
      ? [.buttonReleased(.a), .buttonPressed(.a)]
      : [mode == .whileHeld ? .buttonReleased(.a) : .buttonPressed(.a)]
    let stopped = engine.process(events: disable, from: device, profile: profile, at: 21_000_000)
    #expect(stopped == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test func gyroTimeoutPreservesOtherBindingsOnTheSameStick() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Combined stick",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .rightStick, fullStickDegreesPerSecond: 100),
      bindings: [RemappingBinding(
        source: .axis(.leftStickX),
        destination: .gamepadAxis(.rightStickX),
        axisTuning: RemappingAxisTuning(deadzone: 0)
      )]
    )
    _ = engine.process(
      events: [.leftStickChanged(x: 0.25, y: 0), .motionSample(sample(0, time: 0))],
      from: device,
      profile: profile,
      at: 0
    )
    let combined = engine.process(
      events: [.motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(combined == [.gamepad(
      RemappingGamepadState(axes: [.rightStickX: -0.75, .rightStickY: 0.5]), device
    )])
    let expired = engine.tick(at: 110_000_000)
    #expect(expired == [.gamepad(RemappingGamepadState(axes: [.rightStickX: 0.25]), device)])
    let released = engine.releaseController(device)
    #expect(released == [.gamepad(.neutral, device)])
  }

  @Test(arguments: [false, true])
  func calibrationResetImmediatelyNeutralizesGyroStick(rejectReset: Bool) async throws {
    let virtual = GyroResetGamepadSink()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), gamepadSink: virtual)
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
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
      events: [.motionSample(sample(0, time: 0)), .motionSample(sample(1, time: 10_000_000))],
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
    #expect(await virtual.states == [
      RemappingGamepadState(axes: [.leftStickX: -1, .leftStickY: 0.5]), .neutral
    ])
    #expect(await !engine.hasScheduledOutput())
  }

  @Test func gyroStickUsesAngularSpeedAndNeutralizesAtSampleTimeout() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Gyro stick",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .rightStick, fullStickDegreesPerSecond: 100),
      bindings: []
    )
    _ = engine.process(
      events: [.motionSample(sample(0, time: 0))], from: device, profile: profile, at: 0
    )
    let movement = engine.process(
      events: [.motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(movement == [.gamepad(
      RemappingGamepadState(axes: [.rightStickX: -1, .rightStickY: 0.5]), device
    )])
    #expect(engine.nextScheduledTick(
      after: 10_000_000, continuousIntervalNanoseconds: 8_000_000
    ) == 110_000_000)
    let before = engine.tick(at: 109_999_999)
    #expect(before.isEmpty)
    let expired = engine.tick(at: 110_000_000)
    #expect(expired == [.gamepad(.neutral, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test func mouseUsesSampleTimeAndDoesNotReplayBaselineOrDuplicateSamples() {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = RemappingProfile(
      name: "Gyro mouse",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: RemappingMotionTuning(space: .local, automaticBias: false),
      gyroOutput: RemappingGyroOutput(mode: .mouse, pointerPointsPerDegree: 2),
      bindings: []
    )
    let baseline = engine.process(
      events: [.motionSample(sample(0, time: 0))], from: device, profile: profile, at: 0
    )
    #expect(baseline.isEmpty)
    let movement = engine.process(
      events: [.motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(movement == [.system(.pointerDelta(x: -2, y: -1))])
    let duplicate = engine.process(
      events: [.motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    #expect(duplicate.isEmpty)
    let gap = engine.process(
      events: [.motionSample(sample(2, time: 500_000_000))],
      from: device,
      profile: profile,
      at: 500_000_000
    )
    #expect(gap.isEmpty)
    #expect(engine.tick(at: 510_000_000).isEmpty)
  }

  private func sample(_ index: UInt64, time: UInt64) -> ControllerMotionSample {
    ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: time,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: index,
        basis: .hostEstimate
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 50, y: 100, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        calibrationSource: .nominalDeviceScale
      )
    )
  }
}

private actor GyroResetGamepadSink: RemappingGamepadSink {
  private(set) var states: [RemappingGamepadState] = []
  private var rejectNext = false

  func rejectNextSend() { rejectNext = true }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) throws {
    if rejectNext {
      rejectNext = false
      throw RemappingEventEngineError.sinkUnavailable
    }
    states.append(state)
  }
}
