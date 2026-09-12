/// Independently implemented affine conversion from the Sony calibration report's endpoint facts.
/// Report layout and validation bounds are documented in docs/development/remapping.md.
struct SonyMotionCalibration {
  private struct Axis: Equatable {
    let bias: Double
    let unitsPerCount: Double

    func apply(_ raw: Int16) -> Double { (Double(raw) - bias) * unitsPerCount }
  }

  private let gyro: [Axis]
  private let accel: [Axis]
  private var revision: UInt64 = 0
  private let source: ControllerMotionCalibrationSource

  static let nominal = Self(
    gyro: Array(repeating: Axis(bias: 0, unitsPerCount: 1.0 / 16), count: 3),
    accel: Array(repeating: Axis(bias: 0, unitsPerCount: 1.0 / 8192), count: 3),
    source: .nominalDeviceScale
  )

  static func dualSenseFactory(_ bytes: [UInt8]) -> Self? {
    guard bytes.count == 41, bytes[0] == 5 else { return nil }
    return factory(bytes, groupedGyroEndpoints: false, useBiasedGyroRange: false)
  }

  static func dualShock4Factory(_ bytes: [UInt8], bluetooth: Bool) -> Self? {
    guard bytes.count == (bluetooth ? 41 : 37), bytes[0] == (bluetooth ? 5 : 2)
    else { return nil }
    return factory(bytes, groupedGyroEndpoints: bluetooth, useBiasedGyroRange: true)
  }

  private static func factory(
    _ bytes: [UInt8], groupedGyroEndpoints: Bool, useBiasedGyroRange: Bool
  ) -> Self? {
    func value(_ offset: Int) -> Double {
      Double(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
    }
    let speed = value(19) + value(21)
    var gyro: [Axis] = []
    var accel: [Axis] = []
    for index in 0..<3 {
      let gyroBias = value(1 + index * 2)
      let gyroPlus = value(7 + index * (groupedGyroEndpoints ? 2 : 4))
      let gyroMinus = value(groupedGyroEndpoints ? 13 + index * 2 : 9 + index * 4)
      let gyroRange = useBiasedGyroRange
        ? abs(gyroPlus - gyroBias) + abs(gyroMinus - gyroBias) : gyroPlus - gyroMinus
      let accelPlus = value(23 + index * 4)
      let accelMinus = value(25 + index * 4)
      let accelRange = accelPlus - accelMinus
      guard speed > 0, gyroRange > 0, accelRange > 0 else { return nil }
      let gyroGain = speed / gyroRange
      let accelGain = 2 / accelRange
      let accelBias = (accelPlus + accelMinus) / 2
      guard abs(gyroBias) <= 1024, abs(accelBias) <= 1024,
        (0.5...1.5).contains(gyroGain * 16),
        (0.5...1.5).contains(accelGain * 8192)
      else { return nil }
      gyro.append(Axis(bias: gyroBias, unitsPerCount: gyroGain))
      accel.append(Axis(bias: accelBias, unitsPerCount: accelGain))
    }
    return Self(gyro: gyro, accel: accel, source: .deviceFactory)
  }

  func installed(after previous: Self) -> Self {
    var result = self
    let changed = gyro != previous.gyro || accel != previous.accel || source != previous.source
    result.revision = previous.revision &+ (changed ? 1 : 0)
    return result
  }

  func reading(
    gyro rawGyro: ControllerRawSensorVector, accel rawAccel: ControllerRawSensorVector
  ) -> ControllerMotionReading? {
    ControllerMotionReading(
      gyroscopeDegreesPerSecond: ControllerMotionVector(
        x: gyro[0].apply(rawGyro.x), y: gyro[1].apply(rawGyro.y), z: gyro[2].apply(rawGyro.z)
      ),
      accelerationG: ControllerMotionVector(
        x: accel[0].apply(rawAccel.x), y: accel[1].apply(rawAccel.y), z: accel[2].apply(rawAccel.z)
      ),
      calibrationSource: source,
      calibrationRevision: revision
    )
  }
}
