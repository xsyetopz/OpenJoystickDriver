/// Nintendo reports contain three IMU samples but no reliable device sample timestamp.
/// Estimates their spacing from bounded host receipt intervals, retaining gaps after packet loss.
struct NintendoSensorSamples {
  private var firstReceipt: UInt64?
  private var previousReceipt: UInt64 = 0
  private var previousEnd: UInt64 = 0
  private var averageInterval: UInt64 = 15_000_000
  private var sequence: UInt64 = 0

  mutating func decode(
    _ bytes: [UInt8],
    receivedAt: UInt64,
    layout: NintendoControllerLayout = .pro,
    calibration: NintendoMotionCalibration = .nominal
  ) -> [ControllerEvent] {
    guard bytes.count >= 49 else { return [] }
    let end: UInt64
    let spacing: UInt64
    if let firstReceipt {
      let receipt = max(receivedAt, previousReceipt)
      let delta = receipt - previousReceipt
      // Long gaps are discontinuities, not a new sampling rate. Do not stretch samples over them.
      if (1_000_000...30_000_000).contains(delta) {
        averageInterval = (averageInterval * 7 + delta) / 8
      }
      end = max(previousEnd, receipt - firstReceipt + 10_000_000)
      spacing = min(averageInterval / 3, (end - previousEnd) / 3)
      previousReceipt = receipt
    } else {
      firstReceipt = receivedAt
      previousReceipt = receivedAt
      end = 10_000_000
      spacing = 5_000_000
    }
    previousEnd = end
    return (0..<3).map { index in
      let timestamp = ControllerSampleTimestamp(
        rawCounter: UInt32(bytes[1]),
        elapsedNanoseconds: end - UInt64(2 - index) * spacing,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: sequence,
        basis: .hostEstimate
      )
      sequence += 1
      let offset = 13 + index * 12
      let gyro = Self.vector(bytes, at: offset + 6)
      let accel = Self.vector(bytes, at: offset)
      return .motionSample(
        ControllerMotionSample(
          timestamp: timestamp,
          rawGyroscope: gyro,
          rawAccelerometer: accel,
          physicalReading: calibration.reading(gyro: gyro, accel: accel, layout: layout)
        )
      )
    }
  }

  private static func vector(_ bytes: [UInt8], at offset: Int) -> ControllerRawSensorVector {
    ControllerRawSensorVector(
      x: signed16(bytes, at: offset),
      y: signed16(bytes, at: offset + 2),
      z: signed16(bytes, at: offset + 4)
    )
  }

  private static func signed16(_ bytes: [UInt8], at offset: Int) -> Int16 {
    Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
  }
}
