/// Decodes the two trackpad frames of a Steam Controller state packet.
///
/// The left axis pair alternates between stick and pad when both are active. The pads have no touch
/// clock, so frames carry the report's receipt-anchored motion time.
struct SteamTouchSamples {
  /// The positions in a state packet of the pad flags and coordinates.
  private enum Report {
    /// The byte that holds the pad flags.
    static let buttonByte = 10
    /// Set when the left axis pair holds pad coordinates.
    static let leftPadMask: UInt8 = 0x08
    /// Set when the left pad is touched in a packet whose left axis pair holds the stick.
    static let interleavedLeftMask: UInt8 = 0x80
    /// Set when the right pad is touched.
    static let rightPadMask: UInt8 = 0x10
    /// The offset of the left pad X coordinate.
    static let leftXOffset = 16
    /// The offset of the left pad Y coordinate.
    static let leftYOffset = 18
    /// The offset of the right pad X coordinate.
    static let rightXOffset = 20
    /// The offset of the right pad Y coordinate.
    static let rightYOffset = 22
  }

  /// Signed 16-bit pad coordinates; raw Y grows upward, as the stick Y that shares the right-pad
  /// fields (`SteamControllerDriver.decodeControllerState` negates it to Y-down).
  static let trackpad = ControllerTouchGeometry(
    originX: -32_768,
    originY: -32_768,
    width: 65_536,
    height: 65_536,
    rawYIncreasesUpward: true
  )

  /// The latest left pad X coordinate; zero once the pad is released.
  private var leftX: Int32 = 0
  /// The latest left pad Y coordinate; zero once the pad is released.
  private var leftY: Int32 = 0

  /// The left and right pad frames of the state packet `bytes` at `timestamp`.
  mutating func decode(_ bytes: [UInt8], timestamp: MonotonicTimestamp) -> [ControllerTouchSample] {
    let padPacket = bytes[Report.buttonByte] & Report.leftPadMask != 0
    let interleaved = bytes[Report.buttonByte] & Report.interleavedLeftMask != 0
    if padPacket {
      leftX = signed16(bytes, at: Report.leftXOffset)
      leftY = signed16(bytes, at: Report.leftYOffset)
    } else if !interleaved {
      leftX = 0
      leftY = 0
    }
    return [
      frame(.left, active: padPacket || interleaved, x: leftX, y: leftY, timestamp: timestamp),
      frame(
        .right,
        active: bytes[Report.buttonByte] & Report.rightPadMask != 0,
        x: signed16(bytes, at: Report.rightXOffset),
        y: signed16(bytes, at: Report.rightYOffset),
        timestamp: timestamp
      ),
    ]
  }

  /// The frame of one contact on `surface`, active or not.
  private func frame(
    _ surface: ControllerTouchSurface,
    active: Bool,
    x: Int32,
    y: Int32,
    timestamp: MonotonicTimestamp
  ) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: timestamp,
      contacts: [Self.trackpad.contact(slot: 0, isActive: active, rawX: x, rawY: y)]
    )
  }

  /// The little-endian signed 16-bit value at `offset`.
  private func signed16(_ bytes: [UInt8], at offset: Int) -> Int32 {
    Int32(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
  }
}
