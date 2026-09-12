import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualMotionRoutingTests {
  @Test
  func calibratedMotionStartsAfterBaselineAndNeutralizesAtTimeout() throws {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = try virtualMotionProfile()

    #expect(
      engine.process(
        events: [.motionSample(sample(0, time: 0))],
        from: device,
        profile: profile,
        at: 0
      ).isEmpty
    )
    let output = RemappingVirtualMotionState(
      gyroscopeDegreesPerSecond: ControllerMotionVector(x: 50, y: 100, z: -25),
      accelerationG: ControllerMotionVector(x: 0.25, y: 1, z: -0.5),
      deltaNanoseconds: 10_000_000
    )
    #expect(
      engine.process(
        events: [.motionSample(sample(1, time: 10_000_000))],
        from: device,
        profile: profile,
        at: 10_000_000
      ) == [.motion(output, device)]
    )
    #expect(
      engine.nextScheduledTick(after: 10_000_000, continuousIntervalNanoseconds: 8_000_000)
        == 110_000_000
    )
    #expect(engine.tick(at: 109_999_999).isEmpty)
    #expect(engine.tick(at: 110_000_000) == [.motion(nil, device)])
    #expect(!engine.hasScheduledOutput)
  }

  @Test
  func discontinuityAndProfileReplacementClearStaleMotion() throws {
    var engine = RemappingEngineState()
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = try virtualMotionProfile()
    _ = engine.process(
      events: [.motionSample(sample(0, time: 0)), .motionSample(sample(1, time: 10_000_000))],
      from: device,
      profile: profile,
      at: 10_000_000
    )
    let changedBasis = sample(2, time: 20_000_000, basis: .deviceCounter)
    #expect(
      engine.process(
        events: [.motionSample(changedBasis)],
        from: device,
        profile: profile,
        at: 20_000_000
      ) == [.motion(nil, device)]
    )

    _ = engine.process(
      events: [.motionSample(sample(3, time: 30_000_000, basis: .deviceCounter))],
      from: device,
      profile: profile,
      at: 30_000_000
    )
    #expect(engine.setProfile(nil, for: device) == [.motion(nil, device)])
  }

  @Test
  func profilePersistsVirtualMotionAndRequiresVirtualOutput() throws {
    let profile = try virtualMotionProfile()
    let data = try JSONEncoder().encode(profile)
    #expect(String(bytes: data, encoding: .utf8)?.contains(#""virtual_motion":true"#) == true)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == profile)
    #expect(throws: RemappingValidationError.virtualOutputRequired) {
      try RemappingProfile(
        name: "No virtual output",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        gyroOutput: RemappingGyroOutput(virtualMotion: true),
        bindings: []
      ).validate()
    }
  }

  @Test
  func deliveryFailureNeutralizesMotionAndFaultsUntilRecovery() async throws {
    let output = RejectingMotionSink()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), gamepadSink: output)
    let device = DeviceIdentifier(vendorID: 1, productID: 2)
    let profile = try virtualMotionProfile()
    try await engine.process(
      events: [.motionSample(sample(0, time: 0))],
      from: device,
      using: profile,
      at: 0
    )
    await output.rejectNextMotion()
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        events: [.motionSample(sample(1, time: 10_000_000))],
        from: device,
        using: profile,
        at: 10_000_000
      )
    }
    let values = await output.values
    #expect(values.count == 1)
    #expect(values[0] == nil)
    await #expect(throws: RemappingEventEngineError.faulted) {
      try await engine.tick(at: 20_000_000)
    }
    try await engine.recover()
    #expect(await !engine.hasScheduledOutput())
  }

  private func virtualMotionProfile() throws -> RemappingProfile {
    let profile = RemappingProfile(
      name: "Virtual motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      motionTuning: RemappingMotionTuning(automaticBias: false),
      gyroOutput: RemappingGyroOutput(virtualMotion: true),
      bindings: []
    )
    try profile.validate()
    return profile
  }

  private func sample(
    _ index: UInt64,
    time: UInt64,
    basis: ControllerSampleTimeBasis = .hostEstimate
  ) -> ControllerMotionSample {
    ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: UInt32(index),
        elapsedNanoseconds: time,
        tickNanosecondsNumerator: basis == .deviceCounter ? 1 : nil,
        tickNanosecondsDenominator: basis == .deviceCounter ? 1 : nil,
        sequenceIndex: index,
        basis: basis
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 50, y: 100, z: -25),
        accelerationG: ControllerMotionVector(x: 0.25, y: 1, z: -0.5),
        calibrationSource: .nominalDeviceScale
      )
    )
  }
}

private actor RejectingMotionSink: RemappingGamepadSink {
  private(set) var values: [RemappingVirtualMotionState?] = []
  private var rejectsNextMotion = false

  func rejectNextMotion() { rejectsNextMotion = true }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) {}

  func send(_ motion: RemappingVirtualMotionState?, for identifier: DeviceIdentifier) throws {
    if motion != nil, rejectsNextMotion {
      rejectsNextMotion = false
      throw RemappingEventEngineError.sinkUnavailable
    }
    values.append(motion)
  }
}
