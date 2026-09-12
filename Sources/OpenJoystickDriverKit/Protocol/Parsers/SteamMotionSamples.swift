/// Full Steam Controller state packets carry raw IMU vectors and a sequence number, not time.
struct SteamMotionSamples {
  private var previousCounter: UInt32?
  private var firstReceipt: UInt64?
  private var elapsed: UInt64 = 0
  private var sequence: UInt64 = 0

  mutating func decode(_ bytes: [UInt8], receivedAt: UInt64) -> ControllerMotionSample? {
    guard bytes.count >= 40 else { return nil }
    let counter = UInt32(unsigned16(bytes, at: 4)) | (UInt32(unsigned16(bytes, at: 6)) << 16)
    guard previousCounter != counter else { return nil }
    previousCounter = counter
    if let firstReceipt {
      elapsed = max(elapsed, receivedAt >= firstReceipt ? receivedAt - firstReceipt : 0)
    } else {
      firstReceipt = receivedAt
    }
    let timestamp = ControllerSampleTimestamp(
      rawCounter: counter,
      elapsedNanoseconds: elapsed,
      tickNanosecondsNumerator: nil,
      tickNanosecondsDenominator: nil,
      sequenceIndex: sequence,
      basis: .hostEstimate
    )
    sequence += 1
    let gyro = vector(bytes, at: 34)
    let accel = vector(bytes, at: 28)
    return ControllerMotionSample(
      timestamp: timestamp,
      rawGyroscope: gyro,
      rawAccelerometer: accel,
      physicalReading: ControllerMotionReading(
        gyroscopeDegreesPerSecond: ControllerMotionVector(
          x: Double(gyro.x) * 2000 / 32768,
          y: Double(gyro.z) * 2000 / 32768,
          z: Double(gyro.y) * 2000 / 32768
        ),
        accelerationG: ControllerMotionVector(
          x: Double(accel.x) * 2 / 32768,
          y: Double(accel.z) * 2 / 32768,
          z: -Double(accel.y) * 2 / 32768
        ),
        calibrationSource: .nominalDeviceScale
      )
    )
  }

  private func unsigned16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private func vector(_ bytes: [UInt8], at offset: Int) -> ControllerRawSensorVector {
    ControllerRawSensorVector(
      x: Int16(bitPattern: unsigned16(bytes, at: offset)),
      y: Int16(bitPattern: unsigned16(bytes, at: offset + 2)),
      z: Int16(bitPattern: unsigned16(bytes, at: offset + 4))
    )
  }
}
