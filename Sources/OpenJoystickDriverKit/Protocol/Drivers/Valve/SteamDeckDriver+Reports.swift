public import Foundation

extension SteamDeckDriver {

  /// `SteamDeckStatePacket_t` offsets with the 4-byte `ValveInReportHeader_t` at 0.
  private enum Offset {
    /// The low button word.
    static let buttonsLow = 8
    /// The high button word.
    static let buttonsHigh = 12
    /// The left pad X coordinate; Y follows it.
    static let leftPadX = 16
    /// The right pad X coordinate; Y follows it.
    static let rightPadX = 20
    /// The left trigger.
    static let leftTrigger = 44
    /// The right trigger.
    static let rightTrigger = 46
    /// The left stick X.
    static let leftStickX = 48
    /// The left stick Y.
    static let leftStickY = 50
    /// The right stick X.
    static let rightStickX = 52
    /// The right stick Y.
    static let rightStickY = 54
    /// The left pad pressure.
    static let leftPadPressure = 56
    /// The right pad pressure.
    static let rightPadPressure = 58
  }

  /// The maximum value of a trigger.
  private static let triggerMax: Float = 32767

  /// SDL's output mapping for `ulButtonsL`.
  ///
  /// SDL reports no digital trigger or pad-touch buttons; OJD exposes those bits as the Triton
  /// driver does.
  private static let lowButtons: [(UInt32, Control)] = [
    (0x0000_0001, .rightTrigger), (0x0000_0002, .leftTrigger),
    (0x0000_0004, .rightShoulder), (0x0000_0008, .leftShoulder), (0x0000_0010, .north),
    (0x0000_0020, .east), (0x0000_0040, .west), (0x0000_0080, .south),
    (0x0000_1000, .back), (0x0000_2000, .guide), (0x0000_4000, .start), (0x0000_8000, .leftPaddle2),
    (0x0001_0000, .rightPaddle2), (0x0002_0000, .leftTrackpadClick),
    (0x0004_0000, .rightTrackpadClick), (0x0008_0000, .leftTrackpadTouch),
    (0x0010_0000, .rightTrackpadTouch), (0x0040_0000, .leftStickClick),
    (0x0400_0000, .rightStickClick),
  ]
  /// SDL's output mapping for `ulButtonsH`; QAM is SDL's `STEAM_DECK_QAM` button.
  private static let highButtons: [(UInt32, Control)] = [
    (0x0000_0200, .leftPaddle1), (0x0000_0400, .rightPaddle1), (0x0000_4000, .leftStickTouch),
    (0x0000_8000, .rightStickTouch), (0x0004_0000, .auxiliary1),
  ]
  /// The D-pad up bit of the low button word.
  private static let dpadUp: UInt32 = 0x0100
  /// The D-pad right bit of the low button word.
  private static let dpadRight: UInt32 = 0x0200
  /// The D-pad left bit of the low button word.
  private static let dpadLeft: UInt32 = 0x0400
  /// The D-pad down bit of the low button word.
  private static let dpadDown: UInt32 = 0x0800
  /// The bit of the low button word that shows a finger on the left pad.
  private static let leftPadTouch: UInt32 = 0x0008_0000
  /// The bit of the low button word that shows a finger on the right pad.
  private static let rightPadTouch: UInt32 = 0x0010_0000

  /// Decodes a Deck state report; SDL ignores every other report.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let bytes = Array(data)
    guard bytes.count == steamControllerReportLength, bytes[0] == steamControllerReportPrefix0,
      bytes[1] == steamControllerReportPrefix1, bytes[2] == steamDeckStateMessageID,
      Int(bytes[3]) == steamControllerReportLength
    else { return nil }
    let low = steamUInt32LE(bytes, Offset.buttonsLow)
    let high = steamUInt32LE(bytes, Offset.buttonsHigh)

    var next = state
    for (mask, control) in Self.lowButtons { next.set(control, pressed: low & mask != 0) }
    for (mask, control) in Self.highButtons { next.set(control, pressed: high & mask != 0) }
    next.hat = Self.hat(low)
    next.leftTrigger = trigger(bytes, Offset.leftTrigger)
    next.rightTrigger = trigger(bytes, Offset.rightTrigger)
    next.leftStick = steamStickPosition(bytes, x: Offset.leftStickX, y: Offset.leftStickY)
    next.rightStick = steamStickPosition(bytes, x: Offset.rightStickX, y: Offset.rightStickY)

    let motion = motionSamples.decode(bytes, receivedAt: receivedAt.nanoseconds).map { [$0] } ?? []
    let touch = [
      steamPadFrame(
        .left,
        bytes,
        x: Offset.leftPadX,
        pressure: Offset.leftPadPressure,
        active: low & Self.leftPadTouch != 0,
        receivedAt
      ),
      steamPadFrame(
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

  /// The hat direction of the D-pad bits of `buttons`.
  private static func hat(_ buttons: UInt32) -> HatDirection {
    HatDirection(
      exactUp: buttons & dpadUp != 0,
      right: buttons & dpadRight != 0,
      down: buttons & dpadDown != 0,
      left: buttons & dpadLeft != 0
    )
  }

  /// Raw triggers are unsigned; SDL maps `0...32767` onto its full trigger range.
  private func trigger(_ bytes: [UInt8], _ offset: Int) -> UnipolarValue {
    UnipolarValue(normalized: min(1, Float(steamUInt16LE(bytes, offset)) / Self.triggerMax))
  }
}
