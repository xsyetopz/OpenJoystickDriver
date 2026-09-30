import Foundation

public enum ProtocolPacketFixtures {
  public typealias ByteSticks = (left: (x: UInt8, y: UInt8), right: (x: UInt8, y: UInt8))
  public typealias ByteTriggers = (left: UInt8, right: UInt8)
  public typealias SignedAxes = (x: Int16, y: Int16)
  public typealias WordSticks = (left: (x: UInt16, y: UInt16), right: (x: UInt16, y: UInt16))

  public enum DS3 {
    public static let bluetoothOperationalReportID: UInt8 = 0xF4
    public static let bluetoothOperationalReport: [UInt8] = [0xF4, 0x42, 0x03, 0x00, 0x00]

    public static func inputReport(
      buttons: (first: UInt8, second: UInt8, ps: Bool) = (0, 0, false),
      sticks: ByteSticks = ((128, 128), (128, 128)),
      triggers: ByteTriggers = (0, 0)
    ) -> Data {
      var report = [UInt8](repeating: 0, count: 49)
      report[0] = 0x01
      report[2] = buttons.first
      report[3] = buttons.second
      report[4] = buttons.ps ? 0x01 : 0x00
      report[6] = sticks.left.x
      report[7] = sticks.left.y
      report[8] = sticks.right.x
      report[9] = sticks.right.y
      report[18] = triggers.left
      report[19] = triggers.right
      return Data(report)
    }
  }

  public enum DualSense {
    public static func usbInputReport(
      sticks: ByteSticks = ((128, 128), (128, 128)),
      triggers: ByteTriggers = (0, 0),
      buttons: (first: UInt8, second: UInt8, third: UInt8) = (0x08, 0, 0)
    ) -> Data {
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = 0x01
      report[1] = sticks.left.x
      report[2] = sticks.left.y
      report[3] = sticks.right.x
      report[4] = sticks.right.y
      report[5] = triggers.left
      report[6] = triggers.right
      report[8] = buttons.first
      report[9] = buttons.second
      report[10] = buttons.third
      return Data(report)
    }

    public static func bluetoothInputReport(
      sticks: ByteSticks = ((128, 128), (128, 128)),
      triggers: ByteTriggers = (0, 0),
      buttons: (first: UInt8, second: UInt8, third: UInt8) = (0x08, 0, 0)
    ) -> Data {
      var report = [UInt8](repeating: 0, count: 78)
      report[0] = 0x31
      report[2] = sticks.left.x
      report[3] = sticks.left.y
      report[4] = sticks.right.x
      report[5] = sticks.right.y
      report[6] = triggers.left
      report[7] = triggers.right
      report[9] = buttons.first
      report[10] = buttons.second
      report[11] = buttons.third
      encodeBluetoothCRC(into: &report, transaction: 0xA1)
      return Data(report)
    }

    public static func bluetoothOutputCRC32(_ report: [UInt8]) -> UInt32 {
      bluetoothCRC32(report, transaction: 0xA2)
    }

    public static func bluetoothInputCRC32(_ report: [UInt8]) -> UInt32 {
      bluetoothCRC32(report, transaction: 0xA1)
    }

    private static func encodeBluetoothCRC(into report: inout [UInt8], transaction: UInt8) {
      let crc = bluetoothCRC32(report, transaction: transaction)
      let offset = report.count - 4
      report[offset] = UInt8(truncatingIfNeeded: crc)
      report[offset + 1] = UInt8(truncatingIfNeeded: crc >> 8)
      report[offset + 2] = UInt8(truncatingIfNeeded: crc >> 16)
      report[offset + 3] = UInt8(truncatingIfNeeded: crc >> 24)
    }

    private static func bluetoothCRC32(_ report: [UInt8], transaction: UInt8) -> UInt32 {
      var crc = updateCRC32(0xFFFF_FFFF, byte: transaction)
      for byte in report.dropLast(4) { crc = updateCRC32(crc, byte: byte) }
      return ~crc
    }
  }

  public enum Steam {
    public static func inputReport(
      buttons: (first: UInt8, second: UInt8, third: UInt8) = (0, 0, 0),
      triggers: ByteTriggers = (0, 0),
      left: SignedAxes = (0, 0),
      rightPad: SignedAxes = (0, 0)
    ) -> Data {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<4, with: [0x01, 0x00, 0x01, 60])
      report[8] = buttons.first
      report[9] = buttons.second
      report[10] = buttons.third
      report[11] = triggers.left
      report[12] = triggers.right
      writeInt16LE(left.x, into: &report, at: 16)
      writeInt16LE(left.y, into: &report, at: 18)
      writeInt16LE(rightPad.x, into: &report, at: 20)
      writeInt16LE(rightPad.y, into: &report, at: 22)
      return Data(report)
    }

    public static func wirelessReport(status: UInt8) -> Data {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<5, with: [0x01, 0x00, 0x03, 1, status])
      return Data(report)
    }

    public static var statusReport: Data {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<4, with: [0x01, 0x00, 0x04, 11])
      report[16] = 85
      return Data(report)
    }

    public static let startupSettingsPrefix: [UInt8] = [
      0x87, 9, 0x07, 0x07, 0, 0x08, 0x07, 0, 48, 0x18, 0,
    ]

    public static func writeInt16LE(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
      ProtocolPacketFixtures.writeInt16LE(value, into: &bytes, at: offset)
    }
  }

  public enum SwitchPro {
    public static func inputReport(
      buttons: UInt32 = 0,
      sticks: WordSticks = ((2048, 2048), (2048, 2048))
    ) -> Data {
      var report = [UInt8](repeating: 0, count: 49)
      report[0] = 0x30
      report[3] = UInt8(truncatingIfNeeded: buttons)
      report[4] = UInt8(truncatingIfNeeded: buttons >> 8)
      report[5] = UInt8(truncatingIfNeeded: buttons >> 16)
      writeSwitchStick(x: sticks.left.x, y: sticks.left.y, into: &report, at: 6)
      writeSwitchStick(x: sticks.right.x, y: sticks.right.y, into: &report, at: 9)
      return Data(report)
    }

    public static let usbStartupReportIDs: [UInt8] = [
      0x80, 0x80, 0x80, 0x80, 0x01, 0x01, 0x01, 0x01, 0x01,
    ]
    public static let bluetoothStartupReportIDs: [UInt8] = [0x01, 0x01, 0x01, 0x01, 0x01]
    public static let bluetoothStartupSubcommands: [UInt8] = [0x03, 0x40, 0x48, 0x10, 0x10]
    public static let neutralRumble: [UInt8] = [0x00, 0x01, 0x40, 0x40]
  }

  public enum GIP {
    public static func inputPacket(payload: Data, sequence: UInt8 = 0) -> Data {
      Data([0x20, 0x20, sequence, UInt8(payload.count)]) + payload
    }
  }

  /// Xbox 360 wireless receiver slot envelopes (Linux xpad `xpad360w_process_packet`).
  public enum XUSBReceiver {
    public static let presenceConnected = Data([0x08, 0x80])
    public static let presenceDisconnected = Data([0x08, 0x00])

    /// Pad data: the four-byte envelope with `data[1] == 0x01`, then one wired-format report.
    public static func padData(buttons: UInt16 = 0) -> Data {
      var report = [UInt8](repeating: 0, count: 24)
      report[1] = 0x01
      report[5] = 0x14
      report[6] = UInt8(truncatingIfNeeded: buttons)
      report[7] = UInt8(truncatingIfNeeded: buttons >> 8)
      return Data(report)
    }
  }

  public enum XboxBluetooth {
    public static let neutralInputReport: [UInt8] = [
      1, 0, 128, 0, 128, 0, 128, 0, 128, 0, 0, 0, 0, 0, 0, 0,
    ]
  }

  public enum PassiveUSB {
    public static let emptyConfiguration: [UInt8] = [9, 2, 9, 0, 0, 1, 0, 0x80, 0x32]
    public static let vendorInterface: [UInt8] = [9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0]

    public static func configurationHeader(totalLength: UInt16, interfaces: UInt8 = 1) -> [UInt8] {
      [
        9, 2, UInt8(truncatingIfNeeded: totalLength), UInt8(truncatingIfNeeded: totalLength >> 8),
        interfaces, 1, 0, 0x80, 0x32,
      ]
    }
  }

  private static func writeInt16LE(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
    let raw = UInt16(bitPattern: value)
    bytes[offset] = UInt8(truncatingIfNeeded: raw)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }

  private static func writeSwitchStick(
    x: UInt16,
    y: UInt16,
    into report: inout [UInt8],
    at offset: Int
  ) {
    report[offset] = UInt8(truncatingIfNeeded: x)
    report[offset + 1] = UInt8(truncatingIfNeeded: (x >> 8) | ((y & 0x0F) << 4))
    report[offset + 2] = UInt8(truncatingIfNeeded: y >> 4)
  }

  private static func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
    var crc = current ^ UInt32(byte)
    for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    return crc
  }
}
