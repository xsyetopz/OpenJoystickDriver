/// The left axis pair alternates between stick and pad when both are active.
struct SteamTouchSamples {
  private var leftX: Int32 = 0
  private var leftY: Int32 = 0

  mutating func decode(
    _ bytes: [UInt8],
    timestamp: ControllerSampleTimestamp
  ) -> [ControllerEvent] {
    let padPacket = bytes[10] & 0x08 != 0
    let interleaved = bytes[10] & 0x80 != 0
    if padPacket {
      leftX = signed16(bytes, at: 16)
      leftY = signed16(bytes, at: 18)
    } else if !interleaved {
      leftX = 0
      leftY = 0
    }
    return [
      frame(.left, active: padPacket || interleaved, x: leftX, y: leftY, timestamp: timestamp),
      frame(
        .right,
        active: bytes[10] & 0x10 != 0,
        x: signed16(bytes, at: 20),
        y: signed16(bytes, at: 22),
        timestamp: timestamp
      )
    ]
  }

  private func frame(
    _ surface: ControllerTouchSurface,
    active: Bool,
    x: Int32,
    y: Int32,
    timestamp: ControllerSampleTimestamp
  ) -> ControllerEvent {
    .touchSample(
      ControllerTouchSample(
        reportTimestamp: timestamp,
        rawTouchCounter: nil,
        historyIndex: 0,
        width: 65_536,
        height: 65_536,
        contacts: [ControllerTouchContact(id: 0, isActive: active, x: x, y: y)],
        surface: surface,
        originX: -32_768,
        originY: -32_768
      )
    )
  }

  private func signed16(_ bytes: [UInt8], at offset: Int) -> Int32 {
    Int32(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
  }
}
