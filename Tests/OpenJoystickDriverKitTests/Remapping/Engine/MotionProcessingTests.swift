import Testing

@testable import OpenJoystickDriverKit

struct MotionProcessingTests {
  @Test func manualCalibrationRequiresLiveSamplesAndCancelsOnDiscontinuity() throws {
    var motion = RemappingMotionProcessor()
    let unavailable = motion.startCalibration()
    #expect(!unavailable)
    let tuning = RemappingMotionTuning(automaticBias: false)
    motion.process(sample(sequence: 0, time: 0, yaw: 3), tuning: tuning)
    let started = motion.startCalibration()
    #expect(started && motion.isManuallyCalibrating)
    motion.process(sample(sequence: 1, time: 10_000_000, yaw: 3), tuning: tuning)
    #expect(motion.calibrationOffset.y == 3)
    #expect(motion.latest?.calibratedGyro.y == 0)
    motion.pauseCalibration()
    motion.process(sample(sequence: 2, time: 20_000_000, yaw: 5), tuning: tuning)
    #expect(!motion.isManuallyCalibrating)
    #expect(motion.latest?.calibratedGyro.y == 2)
    let restarted = motion.startCalibration()
    #expect(restarted)
    motion.process(sample(sequence: 3, time: 1_000_000_000, yaw: 5), tuning: tuning)
    #expect(!motion.isManuallyCalibrating)
    #expect(motion.calibrationOffset.y == 0)
    motion.resetCalibration()
    #expect(motion.latest == nil)
  }

  private func sample(
    sequence: UInt64,
    time: UInt64,
    yaw: Double = 90,
    source: ControllerMotionCalibrationSource = .deviceFactory,
    revision: UInt64 = 0
  ) -> ControllerMotionSample {
    ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: time,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: sequence,
        basis: .hostEstimate
      ),
      rawGyroscope: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      rawAccelerometer: ControllerRawSensorVector(x: 0, y: 0, z: 0),
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(x: 0, y: yaw, z: 0),
        accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
        calibrationSource: source,
        calibrationRevision: revision
      )
    )
  }

  @Test func sampleTimeDrivesIntegrationAndDuplicatesCannotRotateTwice() throws {
    var motion = RemappingMotionProcessor()
    motion.process(sample(sequence: 0, time: 0))
    for index in 1...100 {
      motion.process(sample(sequence: UInt64(index), time: UInt64(index) * 10_000_000))
    }
    let result = try #require(motion.latest)
    #expect(abs(result.fused.orientation.rotate(SIMD3(0, 0, 1)).x - 1) < 1e-9)
    let duplicate = motion.process(sample(sequence: 100, time: 1_000_000_000))
    let backward = motion.process(sample(sequence: 101, time: 900_000_000))
    #expect(duplicate == nil && backward == nil)
    #expect(motion.latest?.timestamp == result.timestamp)
    #expect(motion.latest?.fused.orientation == result.fused.orientation)
  }

  @Test func changedCoefficientsResetEvenWhenCalibrationSourceIsUnchanged() throws {
    var motion = RemappingMotionProcessor()
    motion.process(sample(sequence: 0, time: 0, revision: 1))
    motion.process(sample(sequence: 1, time: 10_000_000, revision: 1))
    let rotated = try #require(motion.latest)
    #expect(rotated.fused.orientation != RemappingMotionQuaternion())
    let changed = motion.process(sample(sequence: 2, time: 20_000_000, revision: 2))
    #expect(changed?.deltaTime == 0)
    #expect(changed?.fused.orientation == RemappingMotionQuaternion())
    let next = motion.process(sample(sequence: 3, time: 30_000_000, revision: 2))
    #expect(next?.deltaTime == 0.01)
  }

  @Test func gapAndCalibrationChangeRebaselineWithoutIntegratingMissingTime() throws {
    var motion = RemappingMotionProcessor()
    motion.process(sample(sequence: 0, time: 0))
    motion.process(sample(sequence: 1, time: 10_000_000))
    let gap = motion.process(sample(sequence: 2, time: 1_000_000_000))
    #expect(gap?.deltaTime == 0)
    #expect(gap?.fused.orientation == RemappingMotionQuaternion())
    let changed = motion.process(sample(
      sequence: 3, time: 1_010_000_000, source: .factoryWithUserOffsets
    ))
    #expect(changed?.deltaTime == 0)
    let invalid = motion.process(sample(sequence: 4, time: 1_020_000_000, yaw: 1e308))
    #expect(invalid == nil && motion.latest == nil)
    let recovered = motion.process(sample(sequence: 5, time: 1_030_000_000))
    #expect(recovered?.deltaTime == 0)
  }

  @Test func engineOwnsIndependentMotionAndReleaseStartsFresh() throws {
    var engine = RemappingEngineState()
    let first = DeviceIdentifier(vendorID: 1, productID: 1, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 1, locationID: 2)
    let profile = RemappingProfile(
      name: "Motion state",
      device: RemappingDeviceScope(vendorID: 1, productID: 1),
      applicationScope: .global,
      motionTuning: RemappingMotionTuning(space: .local, yawSensitivity: 2, invertYaw: true),
      bindings: []
    )
    for identifier in [first, second] {
      _ = engine.process(
        events: [.motionSample(sample(sequence: 0, time: 0))],
        from: identifier,
        profile: profile,
        at: 50
      )
    }
    _ = engine.process(
      events: [.motionSample(sample(sequence: 1, time: 10_000_000))],
      from: first,
      profile: profile,
      at: 50
    )
    #expect(engine.devices[first]?.motion.latest?.deltaTime == 0.01)
    #expect(engine.devices[first]?.motion.latest?.tunedGyro.yawDegreesPerSecond == -180)
    #expect(engine.devices[second]?.motion.latest?.timestamp.sequenceIndex == 0)
    let calibration = try engine.calibrateMotion(.start, for: first)
    #expect(calibration.isCollecting)
    #expect(engine.motionCalibrationStatus(for: second)?.isCollecting == false)
    _ = engine.releaseController(first)
    #expect(engine.devices[first] == nil)
    #expect(engine.motionCalibrationStatus(for: first) == nil)
    #expect(throws: RemappingMotionCalibrationError.controllerUnavailable) {
      try engine.calibrateMotion(.start, for: first)
    }
    _ = engine.process(
      events: [.motionSample(sample(sequence: 0, time: 0))],
      from: first,
      profile: profile,
      at: 60
    )
    #expect(engine.devices[first]?.motion.latest?.deltaTime == 0)
    #expect(engine.motionCalibrationStatus(for: first)?.isCollecting == false)
  }
}
