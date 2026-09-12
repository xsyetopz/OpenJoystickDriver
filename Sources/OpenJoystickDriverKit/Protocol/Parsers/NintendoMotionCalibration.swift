/// Independent conversion from Nintendo's SPI IMU calibration coefficients into physical units.
struct NintendoMotionCalibration {
  private let gyroOffsets: [Double]
  private let gyroScales: [Double]
  private let accelScales: [Double]
  private var revision: UInt64 = 0
  private let source: ControllerMotionCalibrationSource

  static let nominal = Self(
    gyroOffsets: [0, 0, 0],
    gyroScales: Array(repeating: 1 / 14.2842, count: 3),
    accelScales: Array(repeating: 1 / 4096, count: 3),
    source: .nominalDeviceScale
  )

  static func factory(_ bytes: [UInt8], userOffsets: [UInt8]? = nil) -> Self? {
    guard bytes.count == 24 else { return nil }
    if let userOffsets {
      guard userOffsets.count == 20, userOffsets[0] == 0xB2, userOffsets[1] == 0xA1
      else { return nil }
    }
    func value(_ offset: Int, from data: [UInt8]) -> Double {
      Double(Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)))
    }
    var gyroOffsets: [Double] = []
    var gyroScales: [Double] = []
    var accelScales: [Double] = []
    for axis in 0..<3 {
      let offset = axis * 2
      let gyroOffset = userOffsets.map { value(14 + offset, from: $0) }
        ?? value(12 + offset, from: bytes)
      let accelOffset = userOffsets.map { value(2 + offset, from: $0) }
        ?? value(offset, from: bytes)
      let gyroRange = value(18 + offset, from: bytes) - gyroOffset
      let accelRange = value(6 + offset, from: bytes) - accelOffset
      // Reject erased flash, degenerate ranges, and reversed coefficients atomically.
      guard gyroRange > 0, accelRange > 0 else { return nil }
      gyroOffsets.append(gyroOffset)
      gyroScales.append(936 / gyroRange)
      accelScales.append(4 / accelRange)
    }
    return Self(
      gyroOffsets: gyroOffsets,
      gyroScales: gyroScales,
      accelScales: accelScales,
      source: userOffsets == nil ? .deviceFactory : .factoryWithUserOffsets
    )
  }

  func installed(after previous: Self) -> Self {
    var result = self
    let changed = gyroOffsets != previous.gyroOffsets || gyroScales != previous.gyroScales
      || accelScales != previous.accelScales || source != previous.source
    result.revision = previous.revision &+ (changed ? 1 : 0)
    return result
  }

  func reading(
    gyro: ControllerRawSensorVector,
    accel: ControllerRawSensorVector,
    layout: NintendoControllerLayout
  ) -> ControllerMotionReading? {
    let rawGyro = [Double(gyro.x), Double(gyro.y), Double(gyro.z)]
    let rawAccel = [Double(accel.x), Double(accel.y), Double(accel.z)]
    let gyroValues = (0..<3).map { (rawGyro[$0] - gyroOffsets[$0]) * gyroScales[$0] }
    // Nintendo's accelerometer offset adjusts sensitivity, not the sampled acceleration.
    let accelValues = (0..<3).map { rawAccel[$0] * accelScales[$0] }
    return ControllerMotionReading(
      gyroscopeDegreesPerSecond: canonical(gyroValues, layout: layout),
      accelerationG: canonical(accelValues, layout: layout),
      calibrationSource: source,
      calibrationRevision: revision
    )
  }

  private func canonical(_ values: [Double], layout: NintendoControllerLayout)
    -> ControllerMotionVector
  {
    let side = layout == .rightJoyCon ? 1.0 : -1.0
    return ControllerMotionVector(x: values[1] * side, y: -values[2] * side, z: -values[0])
  }
}
