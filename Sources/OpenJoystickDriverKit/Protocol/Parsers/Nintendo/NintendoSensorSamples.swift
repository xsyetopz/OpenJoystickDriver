/// Decodes the three IMU samples of a Nintendo report, which carries no reliable device sample
/// timestamp.
///
/// The spacing of the samples comes from bounded host receipt intervals, and gaps after packet loss
/// are kept. Sample time is the first report's receipt time plus the estimated elapsed time, so
/// the newest sample of each report lands up to 10 ms after that report's receipt.
struct NintendoSensorSamples {
  /// The receipt time of the first report of the session.
  private var firstReceipt: UInt64?
  /// The receipt time of the previous report.
  private var previousReceipt: UInt64 = 0
  /// The sample time of the newest sample of the previous report.
  private var previousEnd: UInt64 = 0
  /// The smoothed interval between reports in nanoseconds, starting at 15 ms.
  private var averageInterval: UInt64 = 15_000_000
  /// The sequence index of the next sample; ``reset()`` keeps it.
  private var sequence: UInt64 = 0

  /// Starts a fresh time session at the next report; the sequence index keeps counting.
  mutating func reset() {
    let next = sequence
    self = Self()
    sequence = next
  }

  /// Decodes the samples of the report `bytes`, received at `receivedAt` nanoseconds.
  /// - Returns: Three samples, oldest first; none when the report is shorter than 49 bytes.
  mutating func decode(
    _ bytes: [UInt8],
    receivedAt: UInt64,
    layout: NintendoControllerLayout = .pro,
    calibration: NintendoMotionCalibration = .nominal
  ) -> [ControllerMotionSample] {
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
    let anchor = firstReceipt ?? receivedAt
    return (0..<3).compactMap { index in
      let timestamp = ControllerSampleTimestamp(
        rawCounter: UInt32(bytes[1]),
        monotonic: MonotonicTimestamp(nanoseconds: anchor + end - UInt64(2 - index) * spacing),
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: sequence,
        basis: .hostEstimate
      )
      sequence += 1
      let offset = 13 + index * 12
      return calibration.sample(
        timestamp: timestamp,
        gyro: Self.vector(bytes, at: offset + 6),
        accel: Self.vector(bytes, at: offset),
        layout: layout
      )
    }
  }

  /// The raw vector of the three little-endian values that start at `offset`.
  private static func vector(_ bytes: [UInt8], at offset: Int) -> ControllerRawSensorVector {
    ControllerRawSensorVector(
      x: signed16(bytes, at: offset),
      y: signed16(bytes, at: offset + 2),
      z: signed16(bytes, at: offset + 4)
    )
  }

  /// The little-endian signed 16-bit value at `offset`.
  private static func signed16(_ bytes: [UInt8], at offset: Int) -> Int16 {
    Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
  }
}
