struct RemappingProcessedMotion {
  let timestamp: ControllerSampleTimestamp
  let deltaNanoseconds: UInt64
  let deltaTime: Double
  let calibratedGyro: ControllerMotionVector
  let fused: RemappingFusedMotion
  let tunedGyro: RemappingGyroProjection
}

/// Owns one controller's sample clock, runtime bias, and relative orientation.
struct RemappingMotionProcessor {
  private var previous: ControllerSampleTimestamp?
  private var calibrationSource: ControllerMotionCalibrationSource?
  private var calibrationRevision: UInt64?
  private var bias = RemappingMotionBias()
  private var fusion = RemappingMotionFusion()
  private var transform = RemappingMotionTransform()
  private var previousTuning: RemappingMotionTuning?
  private(set) var latest: RemappingProcessedMotion?
  private(set) var isManuallyCalibrating = false

  var calibrationOffset: ControllerMotionVector {
    ControllerMotionVector(x: bias.offset.x, y: bias.offset.y, z: bias.offset.z)
  }

  /// A live baseline is required; discontinuities cancel collection rather than mix sessions.
  @discardableResult
  mutating func startCalibration() -> Bool {
    guard latest != nil else { return false }
    bias.startManualCollection()
    isManuallyCalibrating = true
    return true
  }

  mutating func pauseCalibration() {
    bias.pauseManualCollection()
    isManuallyCalibrating = false
  }

  mutating func resetCalibration() { resetEstimates() }

  @discardableResult
  mutating func process(
    _ sample: ControllerMotionSample,
    tuning: RemappingMotionTuning = .default
  ) -> RemappingProcessedMotion? {
    let timestamp = sample.timestamp
    if let previous {
      guard timestamp.sequenceIndex > previous.sequenceIndex,
        timestamp.elapsedNanoseconds >= previous.elapsedNanoseconds
      else { return nil }
    }
    guard (try? tuning.validate()) != nil, let reading = sample.physicalReading,
      Self.withinBounds(reading.gyroscopeDegreesPerSecond, limit: 1_000_000),
      Self.withinBounds(reading.accelerationG, limit: 1_000)
    else {
      previous = timestamp
      resetEstimates()
      return nil
    }
    let elapsed = previous.map { timestamp.elapsedNanoseconds - $0.elapsedNanoseconds } ?? 0
    let discontinuity =
      previous == nil || latest == nil || elapsed > 100_000_000 || previousTuning != tuning
      || calibrationRevision != reading.calibrationRevision || previous?.basis != timestamp.basis
      || calibrationSource != reading.calibrationSource
      || previous?.tickNanosecondsNumerator != timestamp.tickNanosecondsNumerator
      || previous?.tickNanosecondsDenominator != timestamp.tickNanosecondsDenominator
    previous = timestamp
    calibrationSource = reading.calibrationSource
    calibrationRevision = reading.calibrationRevision
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
      deltaNanoseconds: elapsed,
      deltaTime: deltaTime,
      calibratedGyro: corrected,
      fused: fused,
      tunedGyro: tuned
    )
    latest = result
    return result
  }

  private mutating func resetEstimates() {
    isManuallyCalibrating = false
    bias.reset()
    fusion.reset()
    transform = RemappingMotionTransform()
    latest = nil
  }

  private static func withinBounds(_ value: ControllerMotionVector, limit: Double) -> Bool {
    value.isFinite && max(abs(value.x), abs(value.y), abs(value.z)) <= limit
  }
}
