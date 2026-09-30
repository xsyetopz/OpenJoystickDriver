/// Unwraps an ordered device counter. A decrease denotes one wrap; a transport reset re-anchors.
/// Multiple wraps during a report gap cannot be recovered from the wire counter alone.
/// Sample time is the first counted report's receipt time plus the unwrapped counter time.
struct SonySensorClock {
  let mask: UInt32
  let tickNumerator: UInt32
  private var anchor: UInt64?
  private var previous: UInt32?
  private var elapsed: UInt64 = 0
  private var remainder: UInt64 = 0
  private var sequence: UInt64 = 0

  init(mask: UInt32, tickNumerator: UInt32) {
    self.mask = mask
    self.tickNumerator = tickNumerator
  }

  /// Starts a new time session at the next report; the sequence index keeps counting.
  mutating func reset() {
    let next = anchor == nil ? sequence : sequence + 1
    self = Self(mask: mask, tickNumerator: tickNumerator)
    sequence = next
  }

  mutating func timestamp(_ counter: UInt32, receivedAt: UInt64) -> ControllerSampleTimestamp {
    let raw = counter & mask
    if let previous {
      let ticks = UInt64((raw &- previous) & mask)
      let scaled = ticks * UInt64(tickNumerator) + remainder
      elapsed += scaled / 3
      remainder = scaled % 3
      sequence += 1
    }
    previous = raw
    let start = anchor ?? receivedAt
    anchor = start
    return ControllerSampleTimestamp(
      rawCounter: raw,
      monotonic: MonotonicTimestamp(nanoseconds: start + elapsed),
      tickNanosecondsNumerator: tickNumerator,
      tickNanosecondsDenominator: 3,
      sequenceIndex: sequence
    )
  }
}

/// The ordered samples of one report.
struct ControllerReportSamples: Equatable {
  var motion: [ControllerMotionSample] = []
  var touch: [ControllerTouchSample] = []
}

/// Packet facts follow Linux hid-playstation; `SonyMotionCalibration.sample` converts to SI.
/// Touch frames carry the report's sensor-clock time: DS4 history frames have no timed counter,
/// so every frame of one report shares that report's time.
enum SonySensorSamples {
  /// hid-playstation `DS4_TOUCHPAD_WIDTH`/`HEIGHT` and `DS_TOUCHPAD_WIDTH`/`HEIGHT`; raw Y grows
  /// downward from the top edge.
  static let dualShock4Touchpad = ControllerTouchGeometry(
    originX: 0,
    originY: 0,
    width: 1920,
    height: 942,
    rawYIncreasesUpward: false
  )
  static let dualSenseTouchpad = ControllerTouchGeometry(
    originX: 0,
    originY: 0,
    width: 1920,
    height: 1080,
    rawYIncreasesUpward: false
  )

  static func dualShock4(
    _ bytes: [UInt8],
    bluetooth: Bool,
    receivedAt: UInt64,
    clock: inout SonySensorClock,
    calibration: SonyMotionCalibration = .nominal
  ) -> ControllerReportSamples {
    guard bytes.count >= 32 else { return ControllerReportSamples() }
    let timestamp = clock.timestamp(UInt32(unsigned16(bytes, at: 9)), receivedAt: receivedAt)
    var samples = ControllerReportSamples(
      motion: motion(bytes, at: 12, timestamp: timestamp, calibration: calibration)
    )
    guard bytes.count > 32 else { return samples }
    let count = Int(bytes[32])
    guard count <= (bluetooth ? 4 : 3), bytes.count >= 33 + count * 9 else { return samples }
    for index in 0..<count {
      let offset = 33 + index * 9
      samples.touch.append(
        ControllerTouchSample(
          timestamp: timestamp.monotonic,
          contacts: contacts(bytes, at: offset + 1, geometry: dualShock4Touchpad)
        )
      )
    }
    return samples
  }

  static func dualSense(
    _ bytes: [UInt8],
    receivedAt: UInt64,
    clock: inout SonySensorClock,
    calibration: SonyMotionCalibration = .nominal
  ) -> ControllerReportSamples {
    guard bytes.count >= 40 else { return ControllerReportSamples() }
    let counter = UInt32(unsigned16(bytes, at: 27)) | (UInt32(unsigned16(bytes, at: 29)) << 16)
    let timestamp = clock.timestamp(counter, receivedAt: receivedAt)
    return ControllerReportSamples(
      motion: motion(bytes, at: 15, timestamp: timestamp, calibration: calibration),
      touch: [
        ControllerTouchSample(
          timestamp: timestamp.monotonic,
          contacts: contacts(bytes, at: 32, geometry: dualSenseTouchpad)
        )
      ]
    )
  }

  /// SDL's `PS5StatePacketAlt_t`, sent by third-party DualSense-protocol controllers: motion at
  /// 15 as in the standard report, a 16-bit microsecond sensor timestamp at 27, and touch
  /// contacts at 31 and 35.
  static func dualSenseAlternate(
    _ bytes: [UInt8],
    receivedAt: UInt64,
    clock: inout SonySensorClock,
    calibration: SonyMotionCalibration = .nominal
  ) -> ControllerReportSamples {
    guard bytes.count >= 39 else { return ControllerReportSamples() }
    let timestamp = clock.timestamp(UInt32(unsigned16(bytes, at: 27)), receivedAt: receivedAt)
    return ControllerReportSamples(
      motion: motion(bytes, at: 15, timestamp: timestamp, calibration: calibration),
      touch: [
        ControllerTouchSample(
          timestamp: timestamp.monotonic,
          contacts: contacts(bytes, at: 31, geometry: dualSenseTouchpad)
        )
      ]
    )
  }

  private static func motion(
    _ bytes: [UInt8],
    at offset: Int,
    timestamp: ControllerSampleTimestamp,
    calibration: SonyMotionCalibration
  ) -> [ControllerMotionSample] {
    let sample = calibration.sample(
      timestamp: timestamp,
      gyro: vector(bytes, at: offset),
      accel: vector(bytes, at: offset + 6)
    )
    return sample.map { [$0] } ?? []
  }

  private static func vector(_ bytes: [UInt8], at offset: Int) -> ControllerRawSensorVector {
    ControllerRawSensorVector(
      x: Int16(bitPattern: unsigned16(bytes, at: offset)),
      y: Int16(bitPattern: unsigned16(bytes, at: offset + 2)),
      z: Int16(bitPattern: unsigned16(bytes, at: offset + 4))
    )
  }

  private static func unsigned16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  /// Slot is the contact's index in the report, as in hid-playstation's `input_mt_slot` loop; the
  /// low seven bits of each contact byte are a per-finger tracking counter and are not published.
  private static func contacts(
    _ bytes: [UInt8],
    at offset: Int,
    geometry: ControllerTouchGeometry
  ) -> [ControllerTouchContact] {
    [offset, offset + 4].enumerated().map { slot, start in
      let x = UInt16(bytes[start + 1]) | (UInt16(bytes[start + 2] & 0x0F) << 8)
      let y = UInt16(bytes[start + 2] >> 4) | (UInt16(bytes[start + 3]) << 4)
      return geometry.contact(
        slot: UInt8(slot),
        isActive: bytes[start] & 0x80 == 0,
        rawX: Int32(x),
        rawY: Int32(y)
      )
    }
  }
}
