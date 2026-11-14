import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerCalibrationTests {
  private static func state(
    left: (Float, Float) = (0, 0),
    right: (Float, Float) = (0, 0),
    triggers: (Float, Float) = (0, 0)
  ) -> ControllerState {
    ControllerState(
      leftStick: StickPosition(x: left.0, y: left.1),
      rightStick: StickPosition(x: right.0, y: right.1),
      leftTrigger: UnipolarValue(normalized: triggers.0),
      rightTrigger: UnipolarValue(normalized: triggers.1)
    )
  }

  private static func rest(_ samples: [ControllerState]) -> ControllerCalibration {
    ControllerCalibration(
      values: ControllerCalibration.capture(.rest, samples: samples, stored: .none).values
    )
  }

  @Test
  func stickThatRestsOffCentreReadsZeroAfterTheRestStep() {
    let recorded = (0..<20).map { _ in Self.state(left: (0.2, -0.1)) }
    let calibration = Self.rest(recorded)
    let calibrated = calibration.applying(to: Self.state(left: (0.2, -0.1)))
    #expect(abs(calibrated.leftStick.x.normalized) < 0.001)
    #expect(abs(calibrated.leftStick.y.normalized) < 0.001)
    #expect(calibrated.rightStick == .center)
  }

  @Test
  func restStepStoresTheMeanOfTheSamples() {
    let values = ControllerCalibration.capture(
      .rest,
      samples: [Self.state(left: (0.1, 0), triggers: (0.1, 0)), Self.state(left: (0.3, 0))],
      stored: .none
    ).values
    #expect(abs((values[.leftStickCenterX] ?? 9) - 0.2) < 0.001)
    #expect(abs((values[.leftTriggerRest] ?? 9) - 0.05) < 0.001)
    #expect(values[.rightStickCenterY] == 0)
  }

  @Test
  func circleStepStoresTheLargestDeflectionAsTheRange() {
    let samples = [
      Self.state(left: (0.8, 0)), Self.state(left: (0, 0.6)), Self.state(left: (-0.8, 0)),
      Self.state(right: (0.5, 0)), Self.state(right: (0, -0.5)),
    ]
    let outcome = ControllerCalibration.capture(.circle, samples: samples, stored: .none)
    #expect(abs((outcome.values[.leftStickRange] ?? 0) - 0.8) < 0.001)
    #expect(abs((outcome.values[.rightStickRange] ?? 0) - 0.5) < 0.001)
    #expect(outcome.unmoved.isEmpty)
    let calibration = ControllerCalibration(values: outcome.values)
    #expect(calibration.applying(to: Self.state(left: (0.8, 0))).leftStick.x == .max)
  }

  @Test
  func circleStepMeasuresFromTheStoredCentre() {
    let stored = ControllerCalibration(values: [.leftStickCenterX: 0.2])
    let outcome = ControllerCalibration.capture(
      .circle,
      samples: [Self.state(left: (1, 0)), Self.state(left: (-0.6, 0))],
      stored: stored
    )
    #expect(abs((outcome.values[.leftStickRange] ?? 0) - 0.8) < 0.001)
  }

  @Test
  func stickThatDoesNotMoveKeepsItsStoredRangeAndIsNamed() {
    let outcome = ControllerCalibration.capture(
      .circle,
      samples: [Self.state(left: (0.9, 0), right: (0.02, 0))],
      stored: ControllerCalibration(values: [.rightStickRange: 0.7])
    )
    #expect(outcome.values[.leftStickRange] != nil)
    #expect(outcome.values[.rightStickRange] == nil)
    #expect(outcome.unmoved == [.rightStickX, .rightStickY])
  }

  @Test
  func triggerStepStoresFullPressAndNamesTheTriggerThatDidNotMove() {
    let outcome = ControllerCalibration.capture(
      .triggers,
      samples: [Self.state(triggers: (0.1, 0.0)), Self.state(triggers: (0.9, 0.0))],
      stored: ControllerCalibration(values: [.rightTriggerFull: 0.8])
    )
    #expect(abs((outcome.values[.leftTriggerFull] ?? 0) - 0.9) < 0.001)
    #expect(outcome.values[.rightTriggerFull] == nil)
    #expect(outcome.unmoved == [.rightTrigger])
  }

  @Test
  func triggerRestAndFullPressScaleTheRangeToZeroThroughOne() {
    let calibration = ControllerCalibration(values: [.leftTriggerRest: 0.1, .leftTriggerFull: 0.9])
    let atRest = calibration.applying(to: Self.state(triggers: (0.1, 0)))
    let pressed = calibration.applying(to: Self.state(triggers: (0.9, 0)))
    #expect(atRest.leftTrigger.rawValue <= 1)
    #expect(pressed.leftTrigger.rawValue >= UInt16.max - 1)
    #expect(pressed.rightTrigger == .min)
  }

  @Test
  func noStoredValueLeavesTheStateUnchanged() {
    let state = Self.state(left: (0.31, -0.77), right: (0.5, 0.5), triggers: (0.4, 0.6))
    #expect(ControllerCalibration.none.applying(to: state) == state)
  }

  @Test
  func calibratedStickStaysInsideTheFullRange() {
    let calibration = ControllerCalibration(values: [.leftStickRange: 0.5])
    let calibrated = calibration.applying(to: Self.state(left: (1, -1)))
    #expect(calibrated.leftStick.x == .max)
    #expect(calibrated.leftStick.y == .min)
  }

  @Test
  func everyCalibrationKeyIsReadByEveryDriver() {
    #expect(ControllerCalibration.keys.allSatisfy(ControllerTuning.Key.alwaysRead.contains))
    #expect(ControllerCalibration.keys.allSatisfy { !$0.hasDriverValue })
    #expect(ControllerCalibration.keys.count == 13)
  }

  @Test
  func tuningCarriesTheCalibrationBesideTheDeadzone() {
    let tuning = ControllerTuning(
      stickDeadzone: 0.1,
      calibration: ControllerCalibration(values: [.leftStickCenterX: 0.25])
    )
    #expect(tuning.text(of: .leftStickCenterX) == "0.25")
    #expect(tuning.text(of: .rightStickRange) == nil)
    #expect(tuning.setKeys == [.stickDeadzone, .leftStickCenterX])
    let higher = ControllerTuning(
      calibration: ControllerCalibration(values: [.leftStickCenterX: 0.5])
    )
    #expect(tuning.overlaid(by: higher).calibration.values == [.leftStickCenterX: 0.5])
    #expect(tuning.keeping([.stickDeadzone]).calibration == .none)
  }

  @Test
  func pipelineAppliesTheCalibrationBeforeDispatchAndKeepsTheRawState() async {
    let driver = OutputCharacterizationTests.ScriptedBatches([[.leftStick(x: 0.2, y: 0)]])
    let stored = ControllerCalibration(values: [.leftStickCenterX: 0.2])
    let source: @Sendable () -> ControllerCalibration = { stored }
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x028E),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: driver,
      dispatcher: OutputCharacterizationTests.PipelineOutput(),
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000,
      calibration: source
    )
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    let calibrated = await pipeline.inputState()
    let raw = await pipeline.rawInputState()
    #expect(abs(calibrated.leftStick.x.normalized) < 0.001)
    #expect(abs(raw.leftStick.x.normalized - 0.2) < 0.001)
    await pipeline.stop()
  }

  private static func sample(gyro: (Double, Double, Double)) throws -> ControllerMotionSample {
    try #require(
      ControllerMotionSample(
        timestamp: ControllerSampleTimestamp(
          rawCounter: 0,
          monotonic: MonotonicTimestamp(nanoseconds: 0),
          tickNanosecondsNumerator: nil,
          tickNanosecondsDenominator: nil,
          sequenceIndex: 0,
          basis: .hostEstimate
        ),
        acceleration: ControllerMotionVector(x: 0, y: 0, z: 9.81),
        angularVelocity: ControllerMotionVector(x: gyro.0, y: gyro.1, z: gyro.2),
        calibrationSource: .nominalDeviceScale
      )
    )
  }

  @Test
  func gyroStepStoresTheMeanAtRestAsTheOffset() {
    let outcome = ControllerCalibration.capture(
      .gyro,
      samples: [],
      gyro: [
        ControllerMotionVector(x: 0.02, y: -0.01, z: 0.0),
        ControllerMotionVector(x: 0.04, y: -0.03, z: 0.02),
      ],
      stored: .none
    )
    #expect(abs((outcome.values[.gyroOffsetX] ?? 9) - 0.03) < 1e-9)
    #expect(abs((outcome.values[.gyroOffsetY] ?? 9) + 0.02) < 1e-9)
    #expect(abs((outcome.values[.gyroOffsetZ] ?? 9) - 0.01) < 1e-9)
    #expect(outcome.unmoved.isEmpty)
  }

  @Test
  func gyroStepOfAControllerWithNoGyroStoresNothing() {
    let outcome = ControllerCalibration.capture(.gyro, samples: [], gyro: [], stored: .none)
    #expect(outcome.values.isEmpty)
    #expect(outcome.unmoved.isEmpty)
  }

  @Test
  func storedGyroOffsetIsRemovedFromEachMotionSample() throws {
    let calibration = ControllerCalibration(values: [.gyroOffsetX: 0.03, .gyroOffsetZ: -0.01])
    let applied = calibration.applying(to: try Self.sample(gyro: (0.03, 0.5, -0.01)))
    #expect(applied.angularVelocity == ControllerMotionVector(x: 0, y: 0.5, z: 0))
    #expect(applied.acceleration == ControllerMotionVector(x: 0, y: 0, z: 9.81))
    let sample = try Self.sample(gyro: (0.1, 0.2, 0.3))
    #expect(ControllerCalibration.none.applying(to: sample) == sample)
  }

  @Test
  func pipelineKeepsTheRawGyroAndRemovesTheStoredOffsetFromTheEvent() async throws {
    let sample = try Self.sample(gyro: (0.03, 0, 0))
    let stored = ControllerCalibration(values: [.gyroOffsetX: 0.03])
    let storedCalibration: @Sendable () -> ControllerCalibration = { stored }
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x028E),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches([[.leftStick(x: 0.2, y: 0)]]),
      dispatcher: OutputCharacterizationTests.PipelineOutput(),
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000,
      calibration: storedCalibration
    )
    await pipeline.start()
    let event = ControllerEvent(
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      state: .neutral,
      motion: [sample]
    )
    await pipeline.handleParsedEvent(event, now: 0)
    #expect(await pipeline.rawAngularVelocity() == ControllerMotionVector(x: 0.03, y: 0, z: 0))
    let normalized = await pipeline.normalized(event)
    #expect(normalized.motion.map(\.angularVelocity) == [ControllerMotionVector(x: 0, y: 0, z: 0)])
    await pipeline.stop()
  }
}
