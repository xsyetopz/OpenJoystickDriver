import Foundation

extension WiiDriver {
  /// The 14-bit reading of each gyro axis and whether its scale is the fast one.
  struct RawGyro: Equatable {
    /// The raw 14-bit yaw.
    var yaw = 0
    /// The raw 14-bit roll.
    var roll = 0
    /// The raw 14-bit pitch.
    var pitch = 0
    /// Whether yaw is on the fast scale.
    var yawFast = false
    /// Whether roll is on the fast scale.
    var rollFast = false
    /// Whether pitch is on the fast scale.
    var pitchFast = false

    /// Whether no axis is on the fast scale.
    var isSlow: Bool { !(yawFast || rollFast || pitchFast) }
  }

  /// The gyro rest offset in degrees per second as pitch, yaw and roll, and the sums that
  /// measure it.
  struct GyroRest {
    /// The sum of the rates of the still frames so far.
    var sum = [0.0, 0.0, 0.0]
    /// The number of still frames in the sum.
    var count = 0
    /// The measured offset; nil while calibrating.
    var offset: [Double]?
    /// The accelerometer reading at the previous gyro frame.
    var lastAcceleration: RawAcceleration?
  }

  /// The extension kinds whose six data bytes are Motion Plus frames.
  static let motionPlusKinds: Set<String> = [
    "MotionPlus", "MotionPlusNunchuk", "MotionPlusClassic",
  ]
  /// The kind whose data a passthrough kind carries between its Motion Plus frames.
  private static let passthroughBases = [
    "MotionPlusNunchuk": "Nunchuk", "MotionPlusClassic": "ClassicController",
  ]
  /// The key of `motionPlusModeBytes` that keeps the kind plugged before activation.
  static let passthroughModeKeys = [
    "Nunchuk": "nunchuk", "ClassicController": "classic", "ClassicControllerPro": "classic",
  ]
  /// The still frames that the rest offset averages (`GyroRestOffset`).
  static let gyroRestWindow = 64
  /// The largest change of a raw accelerometer axis between two frames that counts as still.
  private static let gyroStillTolerance = 4
  /// The reading of a gyro axis at zero rate.
  private static let gyroZero = 8192
  /// Gyro units per degree per second in the slow scale.
  private static let slowUnitsPerDegree = 8192.0 / 595
  /// The fast scale over the slow one: 2000 over 440 degrees per second.
  static let fastOverSlow = 2000.0 / 440

  /// Follows an identified kind: remembers the passthrough base, and tells whether the
  /// activation is due, which is when a handshake finds an inactive Motion Plus
  /// (`MotionPlusActivate`).
  func activatesMotionPlus(after purpose: ExchangePurpose) -> Bool {
    guard case .known(let kind) = extensionKind else {
      motionPlusActive = false
      return false
    }
    if Self.passthroughModeKeys[kind] != nil { passthroughBase = kind }
    if Self.motionPlusKinds.contains(kind) { return false }
    motionPlusActive = false
    return kind == "MotionPlusInactive" && purpose == .extensionHandshake
  }

  /// Takes the gyro of a Motion Plus frame and returns nil, or returns the passthrough
  /// extension's frame in the layout of its own kind; each frame leaves the other's values.
  ///
  /// Byte 5 bit 1 marks a Motion Plus frame. In it the high six bits of each axis sit in bytes 3
  /// to 5, and a set slow flag (byte 3 bits 1 and 0, byte 4 bit 1) means the slow scale. In a
  /// Nunchuk frame the buttons sit two bits higher in byte 5; in a Classic frame the left stick
  /// has lost its low bit and the d-pad left and up sit in bit 0 of bytes 1 and 0.
  func demultiplexMotionPlus(_ data: [UInt8], kind: String) -> (String, [UInt8])? {
    if data[5] & 0x02 != 0 {
      func value(_ low: UInt8, _ high: UInt8) -> Int { Int(low) | Int(high >> 2) << 8 }
      let raw = RawGyro(
        yaw: value(data[0], data[3]),
        roll: value(data[1], data[4]),
        pitch: value(data[2], data[5]),
        yawFast: data[3] & 0x02 == 0,
        rollFast: data[4] & 0x02 == 0,
        pitchFast: data[3] & 0x01 == 0
      )
      gyro = raw
      measureRest(raw)
      return nil
    }
    switch Self.passthroughBases[kind] {
    case "Nunchuk":
      return ("Nunchuk", Array(data[0..<5]) + [data[5] >> 2 & 0x03])
    case let base?:
      let dpad = (data[1] & 1) << 1 | data[0] & 1
      return (
        base,
        [data[0] & 0xFE, data[1] & 0xFE] + Array(data[2..<5]) + [data[5] & 0xFC | dpad]
      )
    default: return nil
    }
  }

  /// The rate of each axis in radians per second, as pitch, yaw and roll for X, Y and Z.
  ///
  /// The signs are the wire's: yaw down, roll left and pitch left are positive.
  func gyroVector(_ raw: RawGyro) -> ControllerMotionVector {
    let rates = Self.degreesPerSecond(raw)
    let offset = gyroRest.offset ?? [0, 0, 0]
    func radians(_ index: Int) -> Double {
      (rates[index] - offset[index]) * ControllerMotionUnits.radiansPerDegree
    }
    return ControllerMotionVector(x: radians(0), y: radians(1), z: radians(2))
  }

  /// The rate of each axis in degrees per second before the offset: pitch, yaw, roll.
  static func degreesPerSecond(_ raw: RawGyro) -> [Double] {
    func rate(_ value: Int, _ fast: Bool) -> Double {
      Double(value - gyroZero) / slowUnitsPerDegree * (fast ? fastOverSlow : 1)
    }
    return [
      rate(raw.pitch, raw.pitchFast), rate(raw.yaw, raw.yawFast), rate(raw.roll, raw.rollFast),
    ]
  }

  /// Measures the rest offset (`GyroRestOffset`).
  ///
  /// It is the mean rate over `gyroRestWindow` consecutive frames in which the remote's
  /// accelerometer is still and no axis is on the fast scale; any other frame restarts the
  /// window. The offset stays once measured.
  private func measureRest(_ raw: RawGyro) {
    guard gyroRest.offset == nil else { return }
    let previous = gyroRest.lastAcceleration
    gyroRest.lastAcceleration = acceleration
    var accelerometerStill = false
    if let before = previous, let now = acceleration {
      let limit = Self.gyroStillTolerance
      accelerometerStill =
        abs(before.x - now.x) <= limit && abs(before.y - now.y) <= limit
        && abs(before.z - now.z) <= limit
    }
    guard accelerometerStill, raw.isSlow else {
      gyroRest.sum = [0, 0, 0]
      gyroRest.count = 0
      return
    }
    gyroRest.sum = zip(gyroRest.sum, Self.degreesPerSecond(raw)).map(+)
    gyroRest.count += 1
    if gyroRest.count == Self.gyroRestWindow {
      gyroRest.offset = gyroRest.sum.map { $0 / Double(Self.gyroRestWindow) }
    }
  }
}
