import Foundation

/// Byte-exact input reports and packets of each protocol family, for tests that feed a driver or
/// parser.
public enum ProtocolPacketFixtures {
  /// Both sticks of a report with one byte per axis.
  public typealias ByteSticks = (left: (x: UInt8, y: UInt8), right: (x: UInt8, y: UInt8))
  /// Both triggers of a report with one byte per trigger.
  public typealias ByteTriggers = (left: UInt8, right: UInt8)
  /// One 16-bit signed stick or pad position.
  public typealias SignedAxes = (x: Int16, y: Int16)
  /// Both sticks of a report with one 16-bit value per axis.
  public typealias WordSticks = (left: (x: UInt16, y: UInt16), right: (x: UInt16, y: UInt16))

  /// DualShock 3 and Sixaxis reports.
  public enum DS3 {
    /// The report ID of the Bluetooth operational-mode feature report.
    public static let bluetoothOperationalReportID: UInt8 = 0xF4
    /// The Bluetooth operational-mode feature report, which starts with its report ID.
    public static let bluetoothOperationalReport: [UInt8] = [0xF4, 0x42, 0x03, 0x00, 0x00]

    /// Builds a 49-byte input report 0x01.
    ///
    /// - Parameters:
    ///   - buttons: The two button bytes and whether the PS button is held.
    ///   - sticks: The left and right stick bytes.
    ///   - triggers: The left and right trigger bytes.
    /// - Returns: The report.
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

  /// DualSense reports and the CRC-32 of its Bluetooth reports.
  public enum DualSense {
    /// Builds a 64-byte USB input report 0x01.
    ///
    /// - Parameters:
    ///   - sticks: The left and right stick bytes.
    ///   - triggers: The left and right trigger bytes.
    ///   - buttons: The three button bytes.
    /// - Returns: The report.
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

    /// Builds a 78-byte Bluetooth input report 0x31 that ends in its CRC-32.
    ///
    /// - Parameters:
    ///   - sticks: The left and right stick bytes.
    ///   - triggers: The left and right trigger bytes.
    ///   - buttons: The three button bytes.
    /// - Returns: The report.
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

    /// Computes the CRC-32 of a Bluetooth output report under transaction byte 0xA2.
    ///
    /// - Parameter report: The report, whose last four bytes hold the checksum and are not covered.
    /// - Returns: The checksum.
    public static func bluetoothOutputCRC32(_ report: [UInt8]) -> UInt32 {
      bluetoothCRC32(report, transaction: 0xA2)
    }

    /// Computes the CRC-32 of a Bluetooth input report under transaction byte 0xA1.
    ///
    /// - Parameter report: The report, whose last four bytes hold the checksum and are not covered.
    /// - Returns: The checksum.
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

  /// Steam Controller reports.
  public enum Steam {
    /// Builds a 64-byte input report.
    ///
    /// - Parameters:
    ///   - buttons: The three button bytes.
    ///   - triggers: The left and right trigger bytes.
    ///   - left: The left pad position.
    ///   - rightPad: The right pad position.
    /// - Returns: The report.
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

    /// Builds a 64-byte wireless connection report.
    ///
    /// - Parameter status: The connection status byte.
    /// - Returns: The report.
    public static func wirelessReport(status: UInt8) -> Data {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<5, with: [0x01, 0x00, 0x03, 1, status])
      return Data(report)
    }

    /// A 64-byte status report whose byte 16 is 85.
    public static var statusReport: Data {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<4, with: [0x01, 0x00, 0x04, 11])
      report[16] = 85
      return Data(report)
    }

    /// The leading bytes of the startup settings write.
    public static let startupSettingsPrefix: [UInt8] = [
      0x87, 12, 0x07, 0x07, 0, 0x08, 0x07, 0, 24, 0, 0, 48, 0x18, 0,
    ]

    /// Stores a 16-bit signed value as two little-endian bytes.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - bytes: The buffer that receives it.
    ///   - offset: The index of the low byte.
    public static func writeInt16LE(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
      ProtocolPacketFixtures.writeInt16LE(value, into: &bytes, at: offset)
    }
  }

  /// Steam Controller (2026) reports, in the layouts of SDL `TritonMTUNoQuat_t`
  /// at `release-3.4.16`.
  public enum Triton {
    /// The grip touch bits of the button word of report `0x42`.
    public enum Grip {
      /// Bit 28, SDL `TRITON_RIGHT_GRIP_TOUCH`.
      public static let right: UInt32 = 0x1000_0000
      /// Bit 29, SDL `TRITON_LEFT_GRIP_TOUCH`.
      public static let left: UInt32 = 0x2000_0000
      /// Bits 0 to 27, every button bit below the grip bits.
      public static let lowerBits: UInt32 = 0x0FFF_FFFF
    }

    /// One state report of the grip fixtures and the button word it carries.
    public typealias GripFixture = (name: String, buttons: UInt32, report: Data)

    /// Builds a 64-byte state report `0x42` with `buttons` in bytes 2 to 5 and zero elsewhere.
    ///
    /// - Parameter buttons: The button word.
    /// - Returns: The report.
    public static func stateReport(buttons: UInt32) -> Data {
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = 0x42
      for index in 0..<4 { report[2 + index] = UInt8(truncatingIfNeeded: buttons >> (8 * index)) }
      return Data(report)
    }

    /// Reports with bit 28 only, bit 29 only, both and neither, each with the other button bits
    /// at zero and with all lower bits set.
    public static let gripReports: [GripFixture] = {
      let combinations: [(String, UInt32)] = [
        ("neither", 0), ("rightOnly", Grip.right), ("leftOnly", Grip.left),
        ("both", Grip.right | Grip.left),
      ]
      return [0, Grip.lowerBits].flatMap { lower in
        combinations.map { name, grips in
          let buttons = grips | lower
          return (
            name: lower == 0 ? name : "\(name)WithLowerBitsSet", buttons: buttons,
            report: stateReport(buttons: buttons)
          )
        }
      }
    }()

    /// The rumble output report: id `0x80`, type 0, intensity 0, speeds, gains 0; 10 bytes.
    ///
    /// - Parameters:
    ///   - left: The left motor speed, at bytes 4 and 5.
    ///   - right: The right motor speed, at bytes 7 and 8.
    /// - Returns: The report bytes, which start with the report ID.
    public static func rumbleReport(left: UInt16, right: UInt16) -> [UInt8] {
      [
        0x80, 0, 0, 0, UInt8(truncatingIfNeeded: left), UInt8(truncatingIfNeeded: left >> 8), 0,
        UInt8(truncatingIfNeeded: right), UInt8(truncatingIfNeeded: right >> 8), 0,
      ]
    }

    /// The pad haptic pulse output report: id `0x81`, side, on, off and repeat count as
    /// little-endian 16-bit values; 8 bytes.
    ///
    /// SDL declares the layout; the side values are
    /// unestablished until a hardware capture.
    ///
    /// - Parameters:
    ///   - side: The side byte.
    ///   - onMicroseconds: The on time.
    ///   - offMicroseconds: The off time.
    ///   - repeatCount: The repeat count.
    /// - Returns: The report bytes, which start with the report ID.
    public static func padPulseReport(
      side: UInt8,
      onMicroseconds: UInt16,
      offMicroseconds: UInt16,
      repeatCount: UInt16
    ) -> [UInt8] {
      [0x81, side]
        + [onMicroseconds, offMicroseconds, repeatCount].flatMap {
          [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)]
        }
    }
  }

  /// Switch Pro Controller reports and startup byte sequences.
  public enum SwitchPro {
    /// Builds a 49-byte input report 0x30.
    ///
    /// - Parameters:
    ///   - buttons: The button bits; their low 24 bits fill bytes 3 to 5.
    ///   - sticks: The left and right stick values, packed as 12-bit pairs.
    /// - Returns: The report.
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

    /// What the driver sends itself over USB; the 0x80 handshake commands are the protocol
    /// description's startup writes.
    public static let usbStartupReportIDs: [UInt8] = [0x01, 0x01, 0x01, 0x01, 0x01]
    /// The Linux USB init slice's handshake commands, in order.
    public static let usbHandshakeCommands: [UInt8] = [0x02, 0x03, 0x02, 0x04]
    /// The report IDs the driver sends itself over Bluetooth at startup.
    public static let bluetoothStartupReportIDs: [UInt8] = [0x01, 0x01, 0x01, 0x01, 0x01]
    /// The subcommand IDs the driver sends over Bluetooth at startup, in order.
    public static let bluetoothStartupSubcommands: [UInt8] = [0x03, 0x40, 0x48, 0x10, 0x10]
    /// The four rumble bytes that request no vibration.
    public static let neutralRumble: [UInt8] = [0x00, 0x01, 0x40, 0x40]
  }

  /// Xbox GIP packets.
  public enum GIP {
    /// Wraps a payload in a GIP input packet header.
    ///
    /// - Parameters:
    ///   - payload: The bytes after the four-byte header.
    ///   - sequence: The sequence byte.
    /// - Returns: The packet.
    public static func inputPacket(payload: Data, sequence: UInt8 = 0) -> Data {
      Data([0x20, 0x20, sequence, UInt8(payload.count)]) + payload
    }
  }

  /// Xbox 360 wireless receiver slot envelopes (Linux xpad `xpad360w_process_packet`).
  public enum XUSBReceiver {
    /// The envelope that reports a pad connected.
    public static let presenceConnected = Data([0x08, 0x80])
    /// The envelope that reports a pad disconnected.
    public static let presenceDisconnected = Data([0x08, 0x00])
    /// The connected envelope with the headset bit (`0x40`) set in byte 1.
    public static let presenceConnectedWithHeadset = Data([0x08, 0xC0])
    /// A pad data envelope one byte shorter than a pad report needs.
    public static let padDataTooShort = padData().dropLast()

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

  /// The three vendor control reads of a ShanWan-class wired Xbox 360 clone.
  ///
  /// The table holds the facts of `paroj/xpad` commit `3470f9f`. The reads go before the first
  /// input read, and each discards its reply.
  public enum XUSBCloneControlReads {
    /// One control read of the table.
    public struct Read: Equatable, Sendable {
      /// The `bmRequestType` byte.
      public let bmRequestType: UInt8
      /// The `bRequest` byte.
      public let bRequest: UInt8
      /// The `wValue` word.
      public let wValue: UInt16
      /// The `wIndex` word.
      public let wIndex: UInt16
      /// The `wLength` word.
      public let wLength: UInt16

      /// Creates a read from its five request fields.
      public init(
        bmRequestType: UInt8,
        bRequest: UInt8,
        wValue: UInt16,
        wIndex: UInt16,
        wLength: UInt16
      ) {
        self.bmRequestType = bmRequestType
        self.bRequest = bRequest
        self.wValue = wValue
        self.wIndex = wIndex
        self.wLength = wLength
      }
    }

    /// The control timeout in milliseconds.
    public static let timeoutMilliseconds = 100
    /// The manufacturer string of the clone that the reads are gated on.
    public static let manufacturer = "SHANWAN"
    /// The reads in the order they are sent.
    public static let reads = [
      Read(bmRequestType: 0xC1, bRequest: 0x01, wValue: 0x0100, wIndex: 0x0000, wLength: 20),
      Read(bmRequestType: 0xC1, bRequest: 0x01, wValue: 0x0000, wIndex: 0x0000, wLength: 8),
      Read(bmRequestType: 0xC0, bRequest: 0x01, wValue: 0x0000, wIndex: 0x0000, wLength: 4),
    ]
  }

  /// Xbox One GIP reports.
  public enum XboxOneGIP {
    /// A neutral input report: GIP command 0x20, options, sequence, length 14, then buttons,
    /// triggers and sticks.
    ///
    /// The Y axes are the complement of zero, which SDL reads as centred.
    public static let neutralInputReport: [UInt8] = [
      0x20, 0, 0, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 0, 0, 0xFF, 0xFF,
    ]
  }

  /// USB configuration descriptors for passive probing.
  public enum PassiveUSB {
    /// A configuration descriptor that declares no interface.
    public static let emptyConfiguration: [UInt8] = [9, 2, 9, 0, 0, 1, 0, 0x80, 0x32]
    /// An interface descriptor of vendor class 0xFF with subclass 0x47 and protocol 0xD0.
    public static let vendorInterface: [UInt8] = [9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0]

    /// Builds a nine-byte configuration descriptor header.
    ///
    /// - Parameters:
    ///   - totalLength: The total length of the configuration descriptor, written little-endian.
    ///   - interfaces: The number of interfaces it declares.
    /// - Returns: The header.
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
