/// Unwraps an ordered device counter. A decrease denotes one wrap; reconnect creates a new clock.
/// Multiple wraps during a report gap cannot be recovered from the wire counter alone.
struct SonySensorClock {
  let mask: UInt32
  let tickNumerator: UInt32
  private var previous: UInt32?
  private var elapsed: UInt64 = 0
  private var remainder: UInt64 = 0
  private var sequence: UInt64 = 0

  init(mask: UInt32, tickNumerator: UInt32) {
    self.mask = mask
    self.tickNumerator = tickNumerator
  }

  mutating func timestamp(_ counter: UInt32) -> ControllerSampleTimestamp {
    let raw = counter & mask
    if let previous {
      let ticks = UInt64((raw &- previous) & mask)
      let scaled = ticks * UInt64(tickNumerator) + remainder
      elapsed += scaled / 3
      remainder = scaled % 3
      sequence += 1
    }
    previous = raw
    return ControllerSampleTimestamp(
      rawCounter: raw,
      elapsedNanoseconds: elapsed,
      tickNanosecondsNumerator: tickNumerator,
      tickNanosecondsDenominator: 3,
      sequenceIndex: sequence
    )
  }
}

/// Packet facts follow Linux hid-playstation; values remain uncalibrated ADC readings.
enum SonySensorSamples {
  static func dualShock4(
    _ bytes: [UInt8],
    bluetooth: Bool,
    clock: inout SonySensorClock,
    calibration: SonyMotionCalibration = .nominal
  ) -> [ControllerEvent] {
    guard bytes.count >= 32 else { return [] }
    let timestamp = clock.timestamp(UInt32(unsigned16(bytes, at: 9)))
    var events: [ControllerEvent] = [
      motion(bytes, at: 12, timestamp: timestamp, calibration: calibration)
    ]
    guard bytes.count > 32 else { return events }
    let count = Int(bytes[32])
    guard count <= (bluetooth ? 4 : 3), bytes.count >= 33 + count * 9 else { return events }
    for index in 0..<count {
      let offset = 33 + index * 9
      events.append(
        .touchSample(
          ControllerTouchSample(
            reportTimestamp: timestamp,
            rawTouchCounter: bytes[offset],
            historyIndex: UInt8(index),
            width: 1920,
            height: 942,
            contacts: contacts(bytes, at: offset + 1)
          )
        )
      )
    }
    return events
  }

  static func dualSense(
    _ bytes: [UInt8],
    clock: inout SonySensorClock,
    calibration: SonyMotionCalibration = .nominal
  ) -> [ControllerEvent] {
    guard bytes.count >= 40 else { return [] }
    let counter = UInt32(unsigned16(bytes, at: 27))
      | (UInt32(unsigned16(bytes, at: 29)) << 16)
    let timestamp = clock.timestamp(counter)
    return [
      motion(bytes, at: 15, timestamp: timestamp, calibration: calibration),
      .touchSample(
        ControllerTouchSample(
          reportTimestamp: timestamp,
          rawTouchCounter: nil,
          historyIndex: 0,
          width: 1920,
          height: 1080,
          contacts: contacts(bytes, at: 32)
        )
      )
    ]
  }

  private static func motion(
    _ bytes: [UInt8],
    at offset: Int,
    timestamp: ControllerSampleTimestamp,
    calibration: SonyMotionCalibration? = nil
  ) -> ControllerEvent {
    let gyro = vector(bytes, at: offset)
    let accel = vector(bytes, at: offset + 6)
    return .motionSample(
      ControllerMotionSample(
        timestamp: timestamp,
        rawGyroscope: gyro,
        rawAccelerometer: accel,
        physicalReading: calibration?.reading(gyro: gyro, accel: accel)
      )
    )
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

  private static func contacts(_ bytes: [UInt8], at offset: Int) -> [ControllerTouchContact] {
    [offset, offset + 4].map { start in
      let x = UInt16(bytes[start + 1]) | (UInt16(bytes[start + 2] & 0x0F) << 8)
      let y = UInt16(bytes[start + 2] >> 4) | (UInt16(bytes[start + 3]) << 4)
      return ControllerTouchContact(
        id: bytes[start] & 0x7F,
        isActive: bytes[start] & 0x80 == 0,
        x: Int32(x),
        y: Int32(y)
      )
    }
  }
}
