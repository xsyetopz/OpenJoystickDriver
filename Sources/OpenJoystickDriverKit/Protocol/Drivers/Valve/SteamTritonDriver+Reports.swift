public import Foundation

extension SteamTritonDriver {

  /// The IDs of the reports the driver reads.
  private enum ReportID {
    /// A state report over USB or a dongle.
    static let state: UInt8 = 0x42
    /// A battery report.
    static let battery: UInt8 = 0x43
    /// A state report over Bluetooth.
    static let bluetoothState: UInt8 = 0x45
    /// A wireless status report.
    static let wirelessStatusX: UInt8 = 0x46
    /// A state report with 16-bit timestamps.
    static let timestampedState: UInt8 = 0x47
    /// A wireless status report.
    static let wirelessStatus: UInt8 = 0x79
  }

  /// Byte offsets with the report ID at 0. `0x47` shares everything through the right stick.
  private enum Offset {
    /// The button words.
    static let buttons = 2
    /// The left trigger.
    static let leftTrigger = 6
    /// The right trigger.
    static let rightTrigger = 8
    /// The left stick X.
    static let leftStickX = 10
    /// The left stick Y.
    static let leftStickY = 12
    /// The right stick X.
    static let rightStickX = 14
    /// The right stick Y.
    static let rightStickY = 16
    /// The accelerometer vector.
    static let imuAccel = 34
    /// The gyro vector.
    static let imuGyro = 40
  }

  /// Pad and IMU timestamp offsets, which differ between the two state layouts.
  private struct PadLayout {
    /// The offset of the left pad X coordinate.
    let leftX: Int
    /// The offset of the right pad X coordinate.
    let rightX: Int
    /// The offset of the IMU timestamp.
    let imuTimestamp: Int
    /// Whether the IMU timestamp is 32 bits; otherwise it is 16 bits.
    let imuTimestampIs32Bit: Bool

    /// `TritonMTUNoQuat_t`: a 32-bit IMU timestamp in microseconds.
    static let microseconds = Self(
      leftX: 18,
      rightX: 24,
      imuTimestamp: 30,
      imuTimestampIs32Bit: true
    )
    /// `TritonMTUNoQuat32TS_t`: a trackpad timestamp first, and a 16-bit IMU timestamp in units
    /// of 32 µs.
    static let units32Microseconds = Self(
      leftX: 20,
      rightX: 26,
      imuTimestamp: 32,
      imuTimestampIs32Bit: false
    )
  }

  /// The shortest state report that is decoded.
  private static let stateReportMinimumLength = 46
  /// The maximum value of a trigger.
  private static let triggerMax: Float = 32767

  /// SDL's output mapping per button bit.
  ///
  /// SDL names bit `0x40` VIEW and bit `0x4000` MENU but reports them as Start and Back, so they
  /// map to `.start` and `.back` here.
  private static let buttonTable: [(UInt32, Control)] = [
    (0x0000_0001, .south), (0x0000_0002, .east), (0x0000_0004, .west),
    (0x0000_0008, .north), (0x0000_0010, .auxiliary1), (0x0000_0020, .rightStickClick),
    (0x0000_0040, .start), (0x0000_0080, .rightPaddle1), (0x0000_0100, .rightPaddle2),
    (0x0000_0200, .rightShoulder), (0x0000_4000, .back), (0x0000_8000, .leftStickClick),
    (0x0001_0000, .guide), (0x0002_0000, .leftPaddle1), (0x0004_0000, .leftPaddle2),
    (0x0008_0000, .leftShoulder), (0x0010_0000, .rightStickTouch),
    (0x0020_0000, .rightTrackpadTouch), (0x0040_0000, .rightTrackpadClick),
    (0x0080_0000, .rightTrigger), (0x0100_0000, .leftStickTouch),
    (0x0200_0000, .leftTrackpadTouch), (0x0400_0000, .leftTrackpadClick),
    (0x0800_0000, .leftTrigger), (0x1000_0000, .rightGripTouch), (0x2000_0000, .leftGripTouch),
  ]
  /// The D-pad down bit of the button word.
  private static let dpadDown: UInt32 = 0x0400
  /// The D-pad right bit of the button word.
  private static let dpadRight: UInt32 = 0x0800
  /// The D-pad left bit of the button word.
  private static let dpadLeft: UInt32 = 0x1000
  /// The D-pad up bit of the button word.
  private static let dpadUp: UInt32 = 0x2000
  /// The bit that shows a finger on the right pad.
  private static let rightPadTouch: UInt32 = 0x0020_0000
  /// The bit that shows a finger on the left pad.
  private static let leftPadTouch: UInt32 = 0x0200_0000

  /// Decodes a state report; battery and wireless status reports update state and carry no input.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let bytes = Array(data)
    guard let id = bytes.first else { return nil }
    switch id {
    case ReportID.state, ReportID.bluetoothState:
      return decodeState(bytes, layout: .microseconds, receivedAt: receivedAt)
    case ReportID.timestampedState:
      return decodeState(bytes, layout: .units32Microseconds, receivedAt: receivedAt)
    case ReportID.battery:
      if isLogicalControllerConnected, bytes.count >= 3 { updatePower(bytes) }
      return nil
    case ReportID.wirelessStatus, ReportID.wirelessStatusX:
      if bytes.count >= 2 { updateWirelessStatus(bytes[1]) }
      return nil
    default: return nil
    }
  }

  /// The event of a state report in `layout`; nil when the report is too short.
  ///
  /// A state report shows a dongle's controller connected.
  private func decodeState(
    _ bytes: [UInt8],
    layout: PadLayout,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard bytes.count >= Self.stateReportMinimumLength else { return nil }
    // Like SDL, a state report is proof that the dongle's controller is connected.
    if !isLogicalControllerConnected { setConnected(true) }
    let buttons = steamUInt32LE(bytes, Offset.buttons)

    var next = state
    for (mask, control) in Self.buttonTable { next.set(control, pressed: buttons & mask != 0) }
    next.hat = Self.hat(buttons)
    next.leftTrigger = trigger(bytes, Offset.leftTrigger)
    next.rightTrigger = trigger(bytes, Offset.rightTrigger)
    next.leftStick = steamStickPosition(bytes, x: Offset.leftStickX, y: Offset.leftStickY)
    next.rightStick = steamStickPosition(bytes, x: Offset.rightStickX, y: Offset.rightStickY)

    var motion: [ControllerMotionSample] = []
    if let sample = motionSample(bytes, layout: layout, receivedAt: receivedAt) {
      motion = [sample]
    }
    let touch = [
      steamPadFrame(
        .left,
        bytes,
        x: layout.leftX,
        pressure: layout.leftX + 4,
        active: buttons & Self.leftPadTouch != 0,
        receivedAt
      ),
      steamPadFrame(
        .right,
        bytes,
        x: layout.rightX,
        pressure: layout.rightX + 4,
        active: buttons & Self.rightPadTouch != 0,
        receivedAt
      ),
    ]
    next.recordTouch(touch)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion, touchFrames: touch)
  }

  /// SDL's sensor frame is (x, z, -y) of the raw axes: X right, Y up, Z toward the player.
  ///
  /// The standard frame takes SDL's +Z as -Y and SDL's +Y as +Z, so it equals the raw axes. SDL
  /// scales 2000 °/s and 2 g per 32768 counts and skips a sample whose timestamp repeats.
  private func motionSample(
    _ bytes: [UInt8],
    layout: PadLayout,
    receivedAt: MonotonicTimestamp
  ) -> ControllerMotionSample? {
    let counter =
      layout.imuTimestampIs32Bit
      ? steamUInt32LE(bytes, layout.imuTimestamp)
      : UInt32(steamUInt16LE(bytes, layout.imuTimestamp))
    guard counter != lastIMUCounter else { return nil }
    lastIMUCounter = counter
    // Thirds of a nanosecond per tick: 1 µs, or 32 µs for the 16-bit counter.
    let clock =
      layout.imuTimestampIs32Bit
      ? SonySensorClock(mask: .max, tickNumerator: 3_000)
      : SonySensorClock(mask: 0xFFFF, tickNumerator: 96_000)
    if imuClock?.mask != clock.mask { imuClock = clock }
    guard var active = imuClock else { return nil }
    let timestamp = active.timestamp(counter, receivedAt: receivedAt.nanoseconds)
    imuClock = active
    let gyroScale = 2000.0 / 32768
    let accelScale = 2.0 / 32768
    return ControllerMotionSample(
      timestamp: timestamp,
      canonicalDegreesPerSecond: vector(bytes, Offset.imuGyro, scale: gyroScale),
      canonicalG: vector(bytes, Offset.imuAccel, scale: accelScale),
      calibrationSource: .nominalDeviceScale
    )
  }

  /// Stores the charging state and battery level of a battery report.
  private func updatePower(_ bytes: [UInt8]) {
    let charging: ControllerConnectionState.Charging =
      switch bytes[1] {
      case 1: .discharging
      case 2: .charging
      case 4: .full
      default: .unknown
      }
    let level = min(bytes[2], 100)
    storedPower = ControllerConnectionState.Power(
      charging: charging,
      battery: BatteryLevel(percentage: level...level),
      wiredPower: charging == .charging || charging == .full ? true : nil
    )
  }

  /// Applies a wireless status: 1 disconnects and 2 connects the logical controller; other values
  /// change nothing.
  private func updateWirelessStatus(_ status: UInt8) {
    switch status {
    case 1: if isLogicalControllerConnected { setConnected(false) }
    case 2: if !isLogicalControllerConnected { setConnected(true) }
    default: break
    }
  }

  /// Sets the connection of the logical controller, queues the change, and resets the input state,
  /// the IMU clock and, on a disconnect, the power.
  private func setConnected(_ connected: Bool) {
    isLogicalControllerConnected = connected
    pendingConnectionStateChange = connected ? .connected : .disconnected
    state = .neutral
    imuClock?.reset()
    lastIMUCounter = nil
    if !connected { storedPower = nil }
  }

  /// The hat direction of the D-pad bits of `buttons`.
  private static func hat(_ buttons: UInt32) -> HatDirection {
    HatDirection(
      exactUp: buttons & dpadUp != 0,
      right: buttons & dpadRight != 0,
      down: buttons & dpadDown != 0,
      left: buttons & dpadLeft != 0
    )
  }

  /// Triggers are signed 16-bit and rest at 0; SDL maps `0...32767` onto its full trigger range.
  private func trigger(_ bytes: [UInt8], _ offset: Int) -> UnipolarValue {
    UnipolarValue(normalized: max(0, min(1, Float(steamInt16LE(bytes, offset)) / Self.triggerMax)))
  }

  /// The vector of three signed 16-bit values at `offset`, multiplied by `scale`.
  private func vector(_ bytes: [UInt8], _ offset: Int, scale: Double) -> ControllerMotionVector {
    ControllerMotionVector(
      x: Double(steamInt16LE(bytes, offset)) * scale,
      y: Double(steamInt16LE(bytes, offset + 2)) * scale,
      z: Double(steamInt16LE(bytes, offset + 4)) * scale
    )
  }
}
