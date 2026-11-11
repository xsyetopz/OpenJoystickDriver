import Foundation

/// Collects a gyro bias offset in degrees per second.
///
/// The offset is an engine estimate; the factory calibration of the device is never changed.
struct RemappingMotionBias {
  /// Current bias offset.
  private(set) var offset = SIMD3<Double>(repeating: 0)
  /// Whether automatic collection found the controller steady and set the offset.
  private(set) var isSteady = false
  /// Time-weighted mean gyro reading of the window.
  private var mean = SIMD3<Double>(repeating: 0)
  /// Smallest gyro reading per axis in the window.
  private var minimumGyro = SIMD3<Double>(repeating: 0)
  /// Largest gyro reading per axis in the window.
  private var maximumGyro = SIMD3<Double>(repeating: 0)
  /// Smallest acceleration reading per axis in the window.
  private var minimumAccel = SIMD3<Double>(repeating: 0)
  /// Largest acceleration reading per axis in the window.
  private var maximumAccel = SIMD3<Double>(repeating: 0)
  /// Time covered by the window in seconds, at most 60.
  private var duration = 0.0
  /// Readings in the window, at most 10000.
  private var samples = 0
  /// Whether manual collection is on.
  private var manual = false

  /// Starts manual collection with an empty window.
  mutating func startManualCollection() {
    clearWindow()
    manual = true
  }
  /// Stops manual collection and empties the window.
  mutating func pauseManualCollection() {
    clearWindow()
    manual = false
  }

  /// Clears the offset and the window.
  mutating func reset() { self = Self() }

  /// Sets the offset and empties the window; returns `false` for a value that is not finite.
  @discardableResult
  mutating func setOffset(_ value: ControllerMotionVector) -> Bool {
    guard value.isFinite else { return false }
    offset = SIMD3(value.x, value.y, value.z)
    clearWindow()
    return true
  }

  /// Returns the gyro reading with the offset removed, and collects it when collection is enabled.
  ///
  /// Collection runs for manual collection, or when `automatic` is set, and only for a time step
  /// from 0 to 0.1 s. Any other time step empties the window.
  mutating func update(
    _ reading: RemappingMotionReading,
    deltaTime: Double,
    automatic: Bool
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

  /// Adds a reading to the window.
  ///
  /// Manual collection takes every reading and sets the offset to the mean at once. Automatic
  /// collection takes only readings near 1 g with a gyro rate of at most 10 degrees per second. It
  /// empties the window when the gyro varies by more than 0.5 degrees per second or the
  /// acceleration by more than 0.025 g, and sets the offset after 2 s and 10 readings.
  private mutating func collect(gyro: SIMD3<Double>, accel: SIMD3<Double>, deltaTime: Double) {
    if !manual {
      let magnitudeSquared = accel.x * accel.x + accel.y * accel.y + accel.z * accel.z
      guard (0.64...1.44).contains(magnitudeSquared),
        max(abs(gyro.x), abs(gyro.y), abs(gyro.z)) <= 10
      else {
        clearWindow()
        return
      }
    }
    if samples == 0 {
      minimumGyro = gyro
      maximumGyro = gyro
      minimumAccel = accel
      maximumAccel = accel
    }
    for axis in 0..<3 {
      minimumGyro[axis] = min(minimumGyro[axis], gyro[axis])
      maximumGyro[axis] = max(maximumGyro[axis], gyro[axis])
      minimumAccel[axis] = min(minimumAccel[axis], accel[axis])
      maximumAccel[axis] = max(maximumAccel[axis], accel[axis])
      if !manual,
        maximumGyro[axis] - minimumGyro[axis] > 0.5
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

  /// Empties the window.
  private mutating func clearWindow() {
    mean = SIMD3(repeating: 0)
    duration = 0
    samples = 0
    isSteady = false
  }
}
