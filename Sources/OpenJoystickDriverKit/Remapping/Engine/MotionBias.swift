import Foundation

/// Per-controller bias collection in degrees/second; never mutates device factory calibration.
struct RemappingMotionBias {
  private(set) var offset = SIMD3<Double>(repeating: 0)
  private(set) var isSteady = false
  private var mean = SIMD3<Double>(repeating: 0)
  private var minimumGyro = SIMD3<Double>(repeating: 0)
  private var maximumGyro = SIMD3<Double>(repeating: 0)
  private var minimumAccel = SIMD3<Double>(repeating: 0)
  private var maximumAccel = SIMD3<Double>(repeating: 0)
  private var duration = 0.0
  private var samples = 0
  private var manual = false

  mutating func startManualCollection() { clearWindow(); manual = true }
  mutating func pauseManualCollection() { clearWindow(); manual = false }

  mutating func reset() { self = Self() }

  @discardableResult mutating func setOffset(_ value: ControllerMotionVector) -> Bool {
    guard value.isFinite else { return false }
    offset = SIMD3(value.x, value.y, value.z)
    clearWindow()
    return true
  }

  mutating func update(
    _ reading: ControllerMotionReading, deltaTime: Double, automatic: Bool
  ) -> ControllerMotionVector {
    let gyro = SIMD3(
      reading.gyroscopeDegreesPerSecond.x,
      reading.gyroscopeDegreesPerSecond.y,
      reading.gyroscopeDegreesPerSecond.z
    )
    let accel = SIMD3(reading.accelerationG.x, reading.accelerationG.y, reading.accelerationG.z)
    if deltaTime.isFinite, deltaTime > 0, deltaTime <= 0.1, manual || automatic {
      collect(gyro: gyro, accel: accel, deltaTime: deltaTime)
    } else {
      clearWindow()
    }
    let corrected = gyro - offset
    return ControllerMotionVector(x: corrected.x, y: corrected.y, z: corrected.z)
  }

  private mutating func collect(gyro: SIMD3<Double>, accel: SIMD3<Double>, deltaTime: Double) {
    if !manual {
      let magnitudeSquared = accel.x * accel.x + accel.y * accel.y + accel.z * accel.z
      guard (0.64...1.44).contains(magnitudeSquared),
        max(abs(gyro.x), abs(gyro.y), abs(gyro.z)) <= 10
      else { clearWindow(); return }
    }
    if samples == 0 {
      minimumGyro = gyro; maximumGyro = gyro
      minimumAccel = accel; maximumAccel = accel
    }
    for axis in 0..<3 {
      minimumGyro[axis] = min(minimumGyro[axis], gyro[axis])
      maximumGyro[axis] = max(maximumGyro[axis], gyro[axis])
      minimumAccel[axis] = min(minimumAccel[axis], accel[axis])
      maximumAccel[axis] = max(maximumAccel[axis], accel[axis])
      if !manual, maximumGyro[axis] - minimumGyro[axis] > 0.5
        || maximumAccel[axis] - minimumAccel[axis] > 0.025
      {
        clearWindow()
        return
      }
    }
    // Time weighting avoids biasing collection toward bursts with more samples per second.
    let weight = deltaTime / (duration + deltaTime)
    mean += (gyro - mean) * weight
    duration = min(60, duration + deltaTime)
    samples = min(10_000, samples + 1)
    if manual {
      offset = mean
    } else if duration >= 2, samples >= 10 {
      offset = mean
      isSteady = true
    }
  }

  private mutating func clearWindow() {
    mean = SIMD3(repeating: 0)
    duration = 0
    samples = 0
    isSteady = false
  }
}
