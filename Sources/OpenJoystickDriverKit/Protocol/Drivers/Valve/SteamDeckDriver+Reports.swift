import Foundation

extension SteamDeckDriver {

  /// `SteamDeckStatePacket_t` offsets with the 4-byte `ValveInReportHeader_t` at 0.
  private enum Offset {
    static let buttonsLow = 8
    static let buttonsHigh = 12
    static let leftPadX = 16
    static let rightPadX = 20
    static let leftTrigger = 44
    static let rightTrigger = 46
    static let leftStickX = 48
    static let leftStickY = 50
    static let rightStickX = 52
    static let rightStickY = 54
    static let leftPadPressure = 56
    static let rightPadPressure = 58
  }

  private static let triggerMax: Float = 32767

  /// SDL's output mapping for `ulButtonsL`. SDL reports no digital trigger or pad-touch buttons;
  /// OJD exposes those bits as the Triton driver does.
  private static let lowButtons: [(UInt32, ControlID)] = [
    (0x0000_0001, .rightTriggerButton), (0x0000_0002, .leftTriggerButton),
    (0x0000_0004, .rightShoulder), (0x0000_0008, .leftShoulder), (0x0000_0010, .faceNorth),
    (0x0000_0020, .faceEast), (0x0000_0040, .faceWest), (0x0000_0080, .faceSouth),
    (0x0000_1000, .view), (0x0000_2000, .guide), (0x0000_4000, .menu), (0x0000_8000, .paddleLeft2),
    (0x0001_0000, .paddleRight2), (0x0002_0000, .leftTrackpadClick),
    (0x0004_0000, .rightTrackpadClick), (0x0008_0000, .leftTrackpadTouch),
    (0x0010_0000, .rightTrackpadTouch), (0x0040_0000, .leftStickClick),
    (0x0400_0000, .rightStickClick),
  ]
  /// SDL's output mapping for `ulButtonsH`; QAM is SDL's `STEAM_DECK_QAM` button.
  private static let highButtons: [(UInt32, ControlID)] = [
    (0x0000_0200, .paddleLeft1), (0x0000_0400, .paddleRight1), (0x0000_4000, .leftStickTouch),
    (0x0000_8000, .rightStickTouch), (0x0004_0000, .auxiliary1),
  ]
  private static let dpadUp: UInt32 = 0x0100
  private static let dpadRight: UInt32 = 0x0200
  private static let dpadLeft: UInt32 = 0x0400
  private static let dpadDown: UInt32 = 0x0800
  private static let leftPadTouch: UInt32 = 0x0008_0000
  private static let rightPadTouch: UInt32 = 0x0010_0000

  /// Decodes a Deck state report; SDL ignores every other report.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    guard bytes.count == steamControllerReportLength, bytes[0] == steamControllerReportPrefix0,
      bytes[1] == steamControllerReportPrefix1, bytes[2] == steamDeckStateMessageID,
      Int(bytes[3]) == steamControllerReportLength
    else { return nil }
    let low = u32(bytes, Offset.buttonsLow)
    let high = u32(bytes, Offset.buttonsHigh)

    var next = state
    for (mask, control) in Self.lowButtons { next.set(control, pressed: low & mask != 0) }
    for (mask, control) in Self.highButtons { next.set(control, pressed: high & mask != 0) }
    next.hat = Self.hat(low)
    next.leftTrigger = trigger(bytes, Offset.leftTrigger)
    next.rightTrigger = trigger(bytes, Offset.rightTrigger)
    next.leftStick = stick(bytes, x: Offset.leftStickX, y: Offset.leftStickY)
    next.rightStick = stick(bytes, x: Offset.rightStickX, y: Offset.rightStickY)

    let motion = motionSamples.decode(bytes, receivedAt: receivedAt.nanoseconds).map { [$0] } ?? []
    let touch = [
      touchFrame(
        .left,
        bytes,
        x: Offset.leftPadX,
        pressure: Offset.leftPadPressure,
        active: low & Self.leftPadTouch != 0,
        receivedAt
      ),
      touchFrame(
        .right,
        bytes,
        x: Offset.rightPadX,
        pressure: Offset.rightPadPressure,
        active: low & Self.rightPadTouch != 0,
        receivedAt
      ),
    ]
    next.recordTouch(touch)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion, touchFrames: touch)
  }

  // swiftlint:disable:next function_parameter_count
  private func touchFrame(
    _ surface: ControllerTouchSurface,
    _ bytes: [UInt8],
    x: Int,
    pressure pressureOffset: Int,
    active: Bool,
    _ receivedAt: MonotonicTimestamp
  ) -> ControllerTouchSample {
    let contact = SteamTouchSamples.trackpad.contact(
      slot: 0,
      isActive: active,
      rawX: Int32(s16(bytes, x)),
      rawY: Int32(s16(bytes, x + 2))
    )
    let pressure = UnipolarValue(normalized: min(1, Float(u16(bytes, pressureOffset)) / 32768))
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

  /// Raw triggers are unsigned; SDL maps `0...32767` onto its full trigger range.
  private func trigger(_ bytes: [UInt8], _ offset: Int) -> UnipolarValue {
    UnipolarValue(normalized: min(1, Float(u16(bytes, offset)) / Self.triggerMax))
  }

  /// Raw stick Y grows upward, so it is negated to Y-down.
  private func stick(_ bytes: [UInt8], x: Int, y: Int) -> StickPosition {
    let rawX = Float(s16(bytes, x)) / steamControllerStickMax
    let rawY = -Float(s16(bytes, y)) / steamControllerStickMax
    return StickPosition(x: max(-1, min(1, rawX)), yDown: max(-1, min(1, rawY)))
  }

  private func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(u16(bytes, offset)) | UInt32(u16(bytes, offset + 2)) << 16
  }

  private func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
  }

  private func s16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
    Int16(bitPattern: u16(bytes, offset))
  }
}
