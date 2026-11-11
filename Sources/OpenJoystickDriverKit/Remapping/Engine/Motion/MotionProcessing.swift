/// A motion reading in the engine's motion space.
///
/// The units are degrees per second and standard gravities in the GamepadMotionHelpers frame (X
/// right, Y up, Z toward the player). Tuning, projections, pointer scales and manual calibration
/// offsets are expressed in it, so converting a sample here keeps their effective sensitivity.
struct RemappingMotionReading {
  /// Angular velocity in degrees per second.
  let gyroscopeDegreesPerSecond: ControllerMotionVector
  /// Acceleration in standard gravities.
  let accelerationG: ControllerMotionVector
}

extension RemappingMotionReading {
  /// Converts a controller sample to the engine frame.
  ///
  /// It inverts the producers' SI conversion and maps canonical (x, y, z) to engine (x, z, -y).
  init(_ sample: ControllerMotionSample) {
    let radians = ControllerMotionUnits.radiansPerDegree
    let gravity = ControllerMotionUnits.standardGravity
    let gyro = sample.angularVelocity
    let accel = sample.acceleration
    gyroscopeDegreesPerSecond = ControllerMotionVector(
      x: gyro.x / radians,
      y: gyro.z / radians,
      z: -gyro.y / radians
    )
    accelerationG = ControllerMotionVector(
      x: accel.x / gravity,
      y: accel.z / gravity,
      z: -accel.y / gravity
    )
  }
}

/// Result of processing one motion sample.
struct RemappingProcessedMotion {
  /// Timestamp of the sample.
  let timestamp: ControllerSampleTimestamp
  /// Seconds since the previous sample, or 0 after a discontinuity.
  let deltaTime: Double
  /// Orientation and gravity after fusion.
  let fused: RemappingFusedMotion
  /// Pitch and yaw rates after projection and tuning.
  let tunedGyro: RemappingGyroProjection
}

/// Processes the motion samples of one controller.
///
/// It owns the sample clock, the runtime bias and the relative orientation.
struct RemappingMotionProcessor {
  /// Timestamp of the previous sample.
  private var previous: ControllerSampleTimestamp?
  /// Calibration source of the previous sample.
  private var calibrationSource: ControllerMotionCalibrationSource?
  /// Calibration revision of the previous sample.
  private var calibrationRevision: UInt64?
  /// Bias collection for the gyro.
  private var bias = RemappingMotionBias()
  /// Orientation fusion of gyro and acceleration.
  private var fusion = RemappingMotionFusion()
  /// Smoothing and scaling of the projected gyro.
  private var transform = RemappingMotionTransform()
  /// Tuning of the previous sample.
  private var previousTuning: RemappingMotionTuning?
  /// Result of the latest sample, or `nil` while there is no baseline.
  private(set) var latest: RemappingProcessedMotion?
  /// Whether manual bias collection runs.
  private(set) var isManuallyCalibrating = false

  /// Gyro bias offset in degrees per second.
  var calibrationOffset: ControllerMotionVector {
    ControllerMotionVector(x: bias.offset.x, y: bias.offset.y, z: bias.offset.z)
  }

  /// Starts manual bias collection and returns whether it started.
  ///
  /// A live baseline is required, and a discontinuity cancels collection rather than mixing
  /// sessions.
  @discardableResult
  mutating func startCalibration() -> Bool {
    guard latest != nil else { return false }
    bias.startManualCollection()
    isManuallyCalibrating = true
    return true
  }

  /// Stops manual bias collection.
  mutating func pauseCalibration() {
    bias.pauseManualCollection()
    isManuallyCalibrating = false
  }

  /// Discards the bias offset, the orientation and the smoothing, and stops manual collection.
  mutating func resetCalibration() { resetEstimates() }

  /// Processes a sample and returns the result, or `nil` when it yields none.
  ///
  /// A sample that is not newer than the previous one yields nothing. So does a sample with invalid
  /// tuning or out-of-range readings, which also resets the estimates. A first sample, a missing
  /// baseline, a gap over 100 ms, or a change of tuning, calibration or time base is a
  /// discontinuity: it resets the estimates and gives a time step of zero.
  @discardableResult
  mutating func process(
    _ sample: ControllerMotionSample,
    tuning: RemappingMotionTuning = .default
  ) -> RemappingProcessedMotion? {
    let timestamp = sample.timestamp
    if let previous {
      guard timestamp.sequenceIndex > previous.sequenceIndex,
        timestamp.monotonic >= previous.monotonic
      else { return nil }
    }
    let reading = RemappingMotionReading(sample)
    guard (try? tuning.validate()) != nil,
      Self.withinBounds(reading.gyroscopeDegreesPerSecond, limit: 1_000_000),
      Self.withinBounds(reading.accelerationG, limit: 1_000)
    else {
      previous = timestamp
      resetEstimates()
      return nil
    }
    let elapsed = previous.map { timestamp.monotonic.nanoseconds - $0.monotonic.nanoseconds } ?? 0
    let discontinuity =
      previous == nil || latest == nil || elapsed > 100_000_000 || previousTuning != tuning
      || calibrationRevision != sample.calibrationRevision || previous?.basis != timestamp.basis
      || calibrationSource != sample.calibrationSource
      || previous?.tickNanosecondsNumerator != timestamp.tickNanosecondsNumerator
      || previous?.tickNanosecondsDenominator != timestamp.tickNanosecondsDenominator
    previous = timestamp
    calibrationSource = sample.calibrationSource
    calibrationRevision = sample.calibrationRevision
    previousTuning = tuning
    if discontinuity { resetEstimates() }
    if elapsed == 0, !discontinuity { return nil }
    let deltaTime = discontinuity ? 0 : Double(elapsed) / 1_000_000_000
    let corrected = bias.update(reading, deltaTime: deltaTime, automatic: tuning.automaticBias)
    guard
      let fused = fusion.update(
        gyro: corrected,
        acceleration: reading.accelerationG,
        deltaTime: deltaTime,
        gravityCorrectionRate: tuning.gravityCorrectionRate
      )
    else {
      latest = nil
      return nil
    }
    guard
      let projected = RemappingMotionProjection.project(
        corrected,
        gravity: fused.gravityG,
        space: tuning.space,
        yawRelaxation: tuning.yawRelaxation,
        sideReductionThreshold: tuning.sideReductionThreshold
      ), let tuned = transform.apply(projected, deltaTime: deltaTime, tuning: tuning)
    else {
      latest = nil
      return nil
    }
    let result = RemappingProcessedMotion(
      timestamp: timestamp,
      deltaTime: deltaTime,
      fused: fused,
      tunedGyro: tuned
    )
    latest = result
    return result
  }

  /// Resets the bias, orientation, smoothing and baseline.
  private mutating func resetEstimates() {
    isManuallyCalibrating = false
    bias.reset()
    fusion.reset()
    transform = RemappingMotionTransform()
    latest = nil
  }

  /// Whether a vector is finite and within a limit on every axis.
  private static func withinBounds(_ value: ControllerMotionVector, limit: Double) -> Bool {
    value.isFinite && max(abs(value.x), abs(value.y), abs(value.z)) <= limit
  }
}
