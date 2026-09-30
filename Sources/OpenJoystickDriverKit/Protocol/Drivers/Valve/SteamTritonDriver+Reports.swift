import Foundation

extension SteamTritonDriver {

  private enum ReportID {
    static let state: UInt8 = 0x42
    static let battery: UInt8 = 0x43
    static let bluetoothState: UInt8 = 0x45
    static let wirelessStatusX: UInt8 = 0x46
    static let timestampedState: UInt8 = 0x47
    static let wirelessStatus: UInt8 = 0x79
  }

  /// Byte offsets with the report ID at 0. `0x47` shares everything through the right stick.
  private enum Offset {
    static let buttons = 2
    static let leftTrigger = 6
    static let rightTrigger = 8
    static let leftStickX = 10
    static let leftStickY = 12
    static let rightStickX = 14
    static let rightStickY = 16
    static let imuAccel = 34
    static let imuGyro = 40
  }

  /// Pad and IMU timestamp offsets, which differ between the two state layouts.
  private struct PadLayout {
    let leftX: Int
    let rightX: Int
    let imuTimestamp: Int
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

  private static let stateReportMinimumLength = 46
  private static let triggerMax: Float = 32767
  private static let stickMax: Float = 32767

  /// Signed 16-bit pad coordinates centered on 0; raw Y grows upward.
  static let trackpad = ControllerTouchGeometry(
    originX: -32_768,
    originY: -32_768,
    width: 65_536,
    height: 65_536,
    rawYIncreasesUpward: true
  )

  /// SDL's output mapping per button bit. SDL names bit `0x40` VIEW and bit `0x4000` MENU but
  /// reports them as Start and Back, so they map to `.menu` and `.view` here.
  private static let buttonTable: [(UInt32, ControlID)] = [
    (0x0000_0001, .faceSouth), (0x0000_0002, .faceEast), (0x0000_0004, .faceWest),
    (0x0000_0008, .faceNorth), (0x0000_0010, .auxiliary1), (0x0000_0020, .rightStickClick),
    (0x0000_0040, .menu), (0x0000_0080, .paddleRight1), (0x0000_0100, .paddleRight2),
    (0x0000_0200, .rightShoulder), (0x0000_4000, .view), (0x0000_8000, .leftStickClick),
    (0x0001_0000, .guide), (0x0002_0000, .paddleLeft1), (0x0004_0000, .paddleLeft2),
    (0x0008_0000, .leftShoulder), (0x0010_0000, .rightStickTouch),
    (0x0020_0000, .rightTrackpadTouch), (0x0040_0000, .rightTrackpadClick),
    (0x0080_0000, .rightTriggerButton), (0x0100_0000, .leftStickTouch),
    (0x0200_0000, .leftTrackpadTouch), (0x0400_0000, .leftTrackpadClick),
    (0x0800_0000, .leftTriggerButton),
  ]
  private static let dpadDown: UInt32 = 0x0400
  private static let dpadRight: UInt32 = 0x0800
  private static let dpadLeft: UInt32 = 0x1000
  private static let dpadUp: UInt32 = 0x2000
  private static let rightPadTouch: UInt32 = 0x0020_0000
  private static let leftPadTouch: UInt32 = 0x0200_0000

  /// Decodes a state report; battery and wireless status reports update state and carry no input.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
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

  private func decodeState(
    _ bytes: [UInt8],
    layout: PadLayout,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard bytes.count >= Self.stateReportMinimumLength else { return nil }
    // Like SDL, a state report is proof that the dongle's controller is connected.
    if !isLogicalControllerConnected { setConnected(true) }
    let buttons = UInt32(u16(bytes, Offset.buttons)) | UInt32(u16(bytes, Offset.buttons + 2)) << 16

    var next = state
    for (mask, control) in Self.buttonTable { next.set(control, pressed: buttons & mask != 0) }
    next.hat = Self.hat(buttons)
    next.leftTrigger = trigger(bytes, Offset.leftTrigger)
    next.rightTrigger = trigger(bytes, Offset.rightTrigger)
    next.leftStick = stick(bytes, x: Offset.leftStickX, y: Offset.leftStickY)
    next.rightStick = stick(bytes, x: Offset.rightStickX, y: Offset.rightStickY)

    var motion: [ControllerMotionSample] = []
    if let sample = motionSample(bytes, layout: layout, receivedAt: receivedAt) {
      motion = [sample]
    }
    let touch = [
      touchFrame(
        .left,
        bytes,
        x: layout.leftX,
        active: buttons & Self.leftPadTouch != 0,
        receivedAt
      ),
      touchFrame(
        .right,
        bytes,
        x: layout.rightX,
        active: buttons & Self.rightPadTouch != 0,
        receivedAt
      ),
    ]
    next.recordTouch(touch)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion, touchFrames: touch)
  }

  /// SDL's sensor frame is (x, z, -y) of the raw axes: X right, Y up, Z toward the player. The
  /// canonical frame takes SDL's +Z as -Y and SDL's +Y as +Z, so it equals the raw axes. SDL
  /// scales 2000 °/s and 2 g per 32768 counts and skips a sample whose timestamp repeats.
  private func motionSample(
    _ bytes: [UInt8],
    layout: PadLayout,
    receivedAt: MonotonicTimestamp
  ) -> ControllerMotionSample? {
    let counter =
      layout.imuTimestampIs32Bit
      ? UInt32(u16(bytes, layout.imuTimestamp)) | UInt32(u16(bytes, layout.imuTimestamp + 2)) << 16
      : UInt32(u16(bytes, layout.imuTimestamp))
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

  private func touchFrame(
    _ surface: ControllerTouchSurface,
    _ bytes: [UInt8],
    x: Int,
    active: Bool,
    _ receivedAt: MonotonicTimestamp
  ) -> ControllerTouchSample {
    let contact = Self.trackpad.contact(
      slot: 0,
      isActive: active,
      rawX: Int32(s16(bytes, x)),
      rawY: Int32(s16(bytes, x + 2))
    )
    let pressure = UnipolarValue(normalized: min(1, Float(u16(bytes, x + 4)) / 32768))
    return ControllerTouchSample(
      surface: surface,
      timestamp: receivedAt,
      contacts: [
        ControllerTouchContact(
          slot: contact.slot,
          isActive: contact.isActive,
          x: contact.x,
          y: contact.y,
          pressure: active ? pressure : nil
        )
      ]
    )
  }

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

  private func updateWirelessStatus(_ status: UInt8) {
    switch status {
    case 1: if isLogicalControllerConnected { setConnected(false) }
    case 2: if !isLogicalControllerConnected { setConnected(true) }
    default: break
    }
  }

  private func setConnected(_ connected: Bool) {
    isLogicalControllerConnected = connected
    pendingConnectionStateChange = connected ? .connected : .disconnected
    state = .neutral
    imuClock?.reset()
    lastIMUCounter = nil
    if !connected { storedPower = nil }
  }

  private static func hat(_ buttons: UInt32) -> HatDirection {
    let up = buttons & dpadUp != 0
    let down = buttons & dpadDown != 0
    let left = buttons & dpadLeft != 0
    let right = buttons & dpadRight != 0
    switch (up, right, down, left) {
    case (true, false, false, false): return .north
    case (true, true, false, false): return .northEast
    case (false, true, false, false): return .east
    case (false, true, true, false): return .southEast
    case (false, false, true, false): return .south
    case (false, false, true, true): return .southWest
    case (false, false, false, true): return .west
    case (true, false, false, true): return .northWest
    default: return .neutral
    }
  }

  /// Triggers are signed 16-bit and rest at 0; SDL maps `0...32767` onto its full trigger range.
  private func trigger(_ bytes: [UInt8], _ offset: Int) -> UnipolarValue {
    UnipolarValue(normalized: max(0, min(1, Float(s16(bytes, offset)) / Self.triggerMax)))
  }

  /// Raw stick Y grows upward, so it is negated to Y-down.
  private func stick(_ bytes: [UInt8], x: Int, y: Int) -> StickPosition {
    let rawX = Float(s16(bytes, x)) / Self.stickMax
    let rawY = -Float(s16(bytes, y)) / Self.stickMax
    return StickPosition(x: max(-1, min(1, rawX)), yDown: max(-1, min(1, rawY)))
  }

  private func vector(_ bytes: [UInt8], _ offset: Int, scale: Double) -> ControllerMotionVector {
    ControllerMotionVector(
      x: Double(s16(bytes, offset)) * scale,
      y: Double(s16(bytes, offset + 2)) * scale,
      z: Double(s16(bytes, offset + 4)) * scale
    )
  }

  private func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private func s16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
    Int16(bitPattern: u16(bytes, offset))
  }
}
