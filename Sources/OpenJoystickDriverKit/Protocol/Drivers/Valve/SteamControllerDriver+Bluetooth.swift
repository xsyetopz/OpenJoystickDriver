import Foundation

/// The legacy Steam Controller's Bluetooth LE framing, from SDL `SDL_hidapi_steam.c`
/// (`WriteSegmentToSteamControllerPacketAssembler`, `SetFeatureReport`,
/// `UpdateBLESteamControllerState`) and `steam/controller_structs.h`.
///
/// Input and feature reports travel as report `0x03` in 20-byte segments: the report ID, a header
/// byte (`0x80` data, `0x40` last, segment number in the low 3 bits), and 18 payload bytes.
/// Reassembled packets are either the wired `0x0001`-versioned layout or the chunked state packet,
/// which the driver rewrites into the 64-byte wired state report its wired decoder reads.
enum SteamBluetooth {
  static let reportID: UInt8 = 0x03
  static let segmentLength = 20
  static let segmentPayloadLength = 18
  static let dataFlag: UInt8 = 0x80
  static let lastFlag: UInt8 = 0x40
  static let segmentNumberMask: UInt8 = 0x07
  /// `SETTING_WIRELESS_PACKET_VERSION`; SDL sets it to 2 before reading Bluetooth state.
  static let wirelessPacketVersionSetting: UInt8 = 49

  /// Splits one feature command into report-`0x03` segments.
  static func featureReports(_ command: [UInt8]) -> [PhysicalHIDOutputReport] {
    let chunks = stride(from: 0, to: max(command.count, 1), by: segmentPayloadLength).map {
      Array(command[$0..<min($0 + segmentPayloadLength, command.count)])
    }
    return chunks.enumerated().map { index, chunk in
      var bytes = [UInt8](repeating: 0, count: segmentLength)
      bytes[0] = reportID
      bytes[1] = dataFlag | UInt8(index) | (index == chunks.count - 1 ? lastFlag : 0)
      bytes.replaceSubrange(2..<(2 + chunk.count), with: chunk)
      return PhysicalHIDOutputReport(reportID: reportID, bytes: bytes)
    }
  }
}

/// Reassembles report-`0x03` segments into one packet, as SDL's packet assembler does.
struct SteamBluetoothAssembler {
  private var buffer: [UInt8] = []
  private var expectedSegment: UInt8 = 0

  /// The completed packet, or nil while segments are still missing or after a framing error.
  mutating func append(_ segment: [UInt8]) -> [UInt8]? {
    guard segment.first == SteamBluetooth.reportID else { return nil }
    guard segment.count == SteamBluetooth.segmentLength else {
      reset()
      return nil
    }
    let header = segment[1]
    guard header & SteamBluetooth.dataFlag != 0 else { return nil }
    let number = header & SteamBluetooth.segmentNumberMask
    if number != expectedSegment {
      reset()
      guard number == 0 else { return nil }
    }
    buffer.append(contentsOf: segment[2...])
    guard header & SteamBluetooth.lastFlag != 0 else {
      expectedSegment += 1
      return nil
    }
    defer { reset() }
    return buffer
  }

  mutating func reset() {
    buffer = []
    expectedSegment = 0
  }
}

/// Keeps the chunked Bluetooth state, since each packet carries only the chunks that changed.
struct SteamBluetoothState {
  private enum Chunk {
    static let buttons0 = 0x0010
    static let triggers = 0x0020
    static let buttons1 = 0x0040
    static let leftStick = 0x0080
    static let leftPad = 0x0100
    static let rightPad = 0x0200
    static let accel = 0x0400
    static let gyro = 0x0800
    static let quaternion = 0x1000
  }

  private enum Wired {
    static let packetNumber = 4
    static let buttons = 8
    static let leftTrigger = 11
    static let leftAxes = 16
    static let rightPad = 20
    static let accel = 28
    static let gyro = 34
    static let quaternion = 40
    static let bleGyroType = 24
    static let bleGyro = 25
    static let leftPadFinger: UInt8 = 0x08
    static let interleavedLeft: UInt8 = 0x80
  }

  private static let chunkedStateType: UInt8 = 4
  private static let bleStateMessageID: UInt8 = 7
  private static let gyroTypeQuaternion: UInt8 = 1
  private static let gyroTypeAccel: UInt8 = 2
  private static let gyroTypeGyro: UInt8 = 3

  private var report: [UInt8] = Self.emptyReport
  private var leftStick: [UInt8] = [0, 0, 0, 0]
  private var leftPad: [UInt8] = [0, 0, 0, 0]
  private var packetNumber: UInt32 = 0

  private static var emptyReport: [UInt8] {
    var bytes = [UInt8](repeating: 0, count: steamControllerReportLength)
    bytes[0] = steamControllerReportPrefix0
    bytes[1] = steamControllerReportPrefix1
    bytes[2] = steamControllerStateMessageID
    bytes[3] = UInt8(steamControllerReportLength - 4)
    return bytes
  }

  /// The wired 64-byte report for one reassembled packet, or nil for a packet with no state.
  /// A chunked packet also returns its left stick, which the wired report carries only while the
  /// left pad is idle.
  mutating func wiredReport(
    from packet: [UInt8]
  ) -> (report: [UInt8], leftStick: (x: Int16, y: Int16)?)? {
    guard packet.count >= 2 else { return nil }
    if packet[0] == steamControllerReportPrefix0, packet[1] == steamControllerReportPrefix1 {
      return wiredVersionReport(packet).map { ($0, nil) }
    }
    guard packet[0] & 0x0F == Self.chunkedStateType, let next = chunkedReport(packet) else {
      return nil
    }
    let x = Int16(bitPattern: UInt16(leftStick[0]) | UInt16(leftStick[1]) << 8)
    let y = Int16(bitPattern: UInt16(leftStick[2]) | UInt16(leftStick[3]) << 8)
    return (next, (x, y))
  }

  /// Type 1 is the wired layout; type 7 carries one IMU vector selected by its gyro data type.
  private mutating func wiredVersionReport(_ packet: [UInt8]) -> [UInt8]? {
    var bytes = Array(packet.prefix(steamControllerReportLength))
    bytes += [UInt8](repeating: 0, count: steamControllerReportLength - bytes.count)
    guard bytes[2] == Self.bleStateMessageID else { return bytes }
    let vector = Array(bytes[Wired.bleGyro..<(Wired.bleGyro + 8)])
    let gyroType = bytes[Wired.bleGyroType]
    var next = report
    next.replaceSubrange(0..<Wired.bleGyroType, with: bytes[0..<Wired.bleGyroType])
    next[2] = steamControllerStateMessageID
    switch gyroType {
    case Self.gyroTypeQuaternion: next.replaceSubrange(Wired.quaternion..<48, with: vector)
    case Self.gyroTypeAccel: next.replaceSubrange(Wired.accel..<34, with: vector.prefix(6))
    case Self.gyroTypeGyro: next.replaceSubrange(Wired.gyro..<40, with: vector.prefix(6))
    default: break
    }
    report = next
    return next
  }

  private mutating func chunkedReport(_ packet: [UInt8]) -> [UInt8]? {
    let mask = Int(packet[0] & 0xF0) | Int(packet[1]) << 8
    var cursor = 2
    func take(_ count: Int) -> [UInt8]? {
      guard cursor + count <= packet.count else { return nil }
      defer { cursor += count }
      return Array(packet[cursor..<(cursor + count)])
    }
    var next = report
    let fields: [(Int, Int, Int?)] = [
      (Chunk.buttons0, 3, Wired.buttons), (Chunk.triggers, 2, Wired.leftTrigger),
      (Chunk.buttons1, 3, Wired.buttons + 5), (Chunk.leftStick, 4, nil), (Chunk.leftPad, 4, nil),
      (Chunk.rightPad, 4, Wired.rightPad), (Chunk.accel, 6, Wired.accel),
      (Chunk.gyro, 6, Wired.gyro), (Chunk.quaternion, 8, Wired.quaternion),
    ]
    for (chunk, length, offset) in fields where mask & chunk != 0 {
      guard let bytes = take(length) else { return nil }
      if let offset {
        next.replaceSubrange(offset..<(offset + length), with: bytes)
      } else if chunk == Chunk.leftStick {
        leftStick = bytes
      } else {
        leftPad = bytes
      }
    }
    // The wired layout shares one left axis pair between stick and pad. A touched pad fills it
    // and marks the report interleaved, so the wired decoder keeps the stick it was given.
    let padTouched = next[Wired.buttons + 2] & Wired.leftPadFinger != 0
    next[Wired.buttons + 2] &= ~Wired.interleavedLeft
    if padTouched { next[Wired.buttons + 2] |= Wired.interleavedLeft }
    next.replaceSubrange(
      Wired.leftAxes..<(Wired.leftAxes + 4),
      with: padTouched ? leftPad : leftStick
    )
    packetNumber &+= 1
    for index in 0..<4 {
      next[Wired.packetNumber + index] = UInt8(truncatingIfNeeded: packetNumber >> (8 * index))
    }
    report = next
    return next
  }
}
