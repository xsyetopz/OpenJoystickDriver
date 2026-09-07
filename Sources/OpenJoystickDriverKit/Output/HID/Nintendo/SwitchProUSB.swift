import Foundation

/// USB Nintendo Switch Pro HID surface used by SDL HIDAPI Nintendo and
/// Apple GameController. Input report `0x30` matches Linux `hid-nintendo` /
/// `SwitchProParser`. USB handshake `0x80`/`0x81` and subcommand ACK `0x21`
/// are included so a consumer can complete init. Reports are padded to the
/// captured 64-byte HID lengths. Bluetooth UART is out of scope.
public enum SwitchProUSBHIDDescriptor {
  public static let reportID: UInt8 = 0x30
  public static let inputReportLength = 64
  public static let usbCommandReportID: UInt8 = 0x80
  public static let usbCommandReplyReportID: UInt8 = 0x81
  public static let subcommandReportID: UInt8 = 0x01
  public static let subcommandAckReportID: UInt8 = 0x21
  public static let rumbleReportID: UInt8 = 0x10
  public static let outputReportLength = 64
  public static let usbBatteryAndConnection: UInt8 = 0x91
  public static let proControllerDeviceType: UInt8 = 0x03
  public static let spiFlashReadSubcommand: UInt8 = 0x10
  public static let requestDeviceInfoSubcommand: UInt8 = 0x02

  /// Captured USB HID report descriptor for `057E:2009` (Joystick, report `0x30`).
  public static let descriptor: [UInt8] = [
    0x05, 0x01, 0x15, 0x00, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x30, 0x05, 0x01,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0A, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01,
    0x95, 0x0A, 0x55, 0x00, 0x65, 0x00, 0x81, 0x02, 0x05, 0x09, 0x19, 0x0B,
    0x29, 0x0E, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x04, 0x81, 0x02,
    0x75, 0x01, 0x95, 0x02, 0x81, 0x03, 0x0B, 0x01, 0x00, 0x01, 0x00, 0xA1,
    0x00, 0x0B, 0x30, 0x00, 0x01, 0x00, 0x0B, 0x31, 0x00, 0x01, 0x00, 0x0B,
    0x32, 0x00, 0x01, 0x00, 0x0B, 0x35, 0x00, 0x01, 0x00, 0x15, 0x00, 0x27,
    0xFF, 0xFF, 0x00, 0x00, 0x75, 0x10, 0x95, 0x04, 0x81, 0x02, 0xC0, 0x0B,
    0x39, 0x00, 0x01, 0x00, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B,
    0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81, 0x02, 0x05, 0x09, 0x19,
    0x0F, 0x29, 0x12, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x04, 0x81,
    0x02, 0x75, 0x08, 0x95, 0x34, 0x81, 0x03, 0x06, 0x00, 0xFF, 0x85, 0x21,
    0x09, 0x01, 0x75, 0x08, 0x95, 0x3F, 0x81, 0x03, 0x85, 0x81, 0x09, 0x02,
    0x75, 0x08, 0x95, 0x3F, 0x81, 0x03, 0x85, 0x01, 0x09, 0x03, 0x75, 0x08,
    0x95, 0x3F, 0x91, 0x83, 0x85, 0x10, 0x09, 0x04, 0x75, 0x08, 0x95, 0x3F,
    0x91, 0x83, 0x85, 0x80, 0x09, 0x05, 0x75, 0x08, 0x95, 0x3F, 0x91, 0x83,
    0x85, 0x82, 0x09, 0x06, 0x75, 0x08, 0x95, 0x3F, 0x91, 0x83, 0xC0,
  ]
}

public struct SwitchProUSBHIDReportFormat: VirtualGamepadReportFormat {
  public let descriptor: [UInt8] = SwitchProUSBHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = SwitchProUSBHIDDescriptor.inputReportLength - 1
  public let inputReportID: UInt8? = SwitchProUSBHIDDescriptor.reportID
  public let outputReportPayloadSize: Int? = SwitchProUSBHIDDescriptor.outputReportLength - 1
  public let outputReportID: UInt8? = SwitchProUSBHIDDescriptor.subcommandReportID

  public init() {}

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: SwitchProUSBHIDDescriptor.inputReportLength)
    report[0] = SwitchProUSBHIDDescriptor.reportID
    report[2] = SwitchProUSBHIDDescriptor.usbBatteryAndConnection
    let buttons = SwitchProHIDBits.buttons(state)
    report[3] = UInt8(truncatingIfNeeded: buttons)
    report[4] = UInt8(truncatingIfNeeded: buttons >> 8)
    report[5] = UInt8(truncatingIfNeeded: buttons >> 16)
    SwitchProHIDBits.writeStick(
      x: state.leftStickX,
      y: state.leftStickY,
      into: &report,
      at: 6
    )
    SwitchProHIDBits.writeStick(
      x: state.rightStickX,
      y: state.rightStickY,
      into: &report,
      at: 9
    )
    return report
  }

  public func inputReportRespondingToHostOutput(_ bytes: [UInt8]) -> [UInt8]? {
    guard let reportID = bytes.first else { return nil }
    switch reportID {
    case SwitchProUSBHIDDescriptor.usbCommandReportID:
      let command = bytes.count > 1 ? bytes[1] : 0
      return SwitchProHIDBits.usbCommandReply(command)
    case SwitchProUSBHIDDescriptor.subcommandReportID:
      let subcommand = bytes.count > 10 ? bytes[10] : 0
      let payload = bytes.count > 11 ? Array(bytes[11...]) : []
      return SwitchProHIDBits.subcommandAck(subcommand, payload: payload)
    default:
      return nil
    }
  }

  public func hostGetReport(reportID: UInt32, maxSize: Int) -> [UInt8]? {
    let id = UInt8(truncatingIfNeeded: reportID)
    let reply: [UInt8]
    switch id {
    case SwitchProUSBHIDDescriptor.usbCommandReplyReportID:
      reply = SwitchProHIDBits.usbCommandReply(0x01)
    case SwitchProUSBHIDDescriptor.subcommandAckReportID:
      reply = SwitchProHIDBits.subcommandAck(0x00, payload: [])
    case SwitchProUSBHIDDescriptor.reportID:
      return nil
    default:
      reply = [UInt8](repeating: 0, count: SwitchProUSBHIDDescriptor.inputReportLength)
    }
    return Array(reply.prefix(max(0, maxSize)))
  }
}

enum SwitchProHIDBits {
  private static let stickCenter: UInt16 = 2048
  private static let stickExtent = 2047
  private static let factoryCenter: UInt16 = 0x0800
  private static let factoryExtent: UInt16 = 0x05DC
  private static let syntheticMAC: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x00, 0x02]

  static func buttons(_ state: VirtualGamepadState) -> UInt32 {
    var bits: UInt32 = 0
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.x.rawValue) { bits |= 0x0000_0001 }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.y.rawValue) { bits |= 0x0000_0002 }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.a.rawValue) { bits |= 0x0000_0004 }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.b.rawValue) { bits |= 0x0000_0008 }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.rightBumper.rawValue) {
      bits |= 0x0000_0040
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.rightStick.rawValue) {
      bits |= 0x0000_0400
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.leftStick.rawValue) {
      bits |= 0x0000_0800
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.back.rawValue) {
      bits |= 0x0000_0100
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.start.rawValue) {
      bits |= 0x0000_0200
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.guide.rawValue) {
      bits |= 0x0000_1000
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.share.rawValue) {
      bits |= 0x0000_2000
    }
    if isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.leftBumper.rawValue) {
      bits |= 0x0040_0000
    }
    if state.rightTrigger > 0 { bits |= 0x0000_0080 }
    if state.leftTrigger > 0 { bits |= 0x0080_0000 }
    bits |= dpadBits(state.hat)
    return bits
  }

  static func writeStick(x: Int16, y: Int16, into report: inout [UInt8], at offset: Int) {
    let packedX = stick12(x, invert: false)
    let packedY = stick12(y, invert: true)
    report[offset] = UInt8(truncatingIfNeeded: packedX)
    report[offset + 1] = UInt8(truncatingIfNeeded: (packedX >> 8) | ((packedY & 0x0F) << 4))
    report[offset + 2] = UInt8(truncatingIfNeeded: packedY >> 4)
  }

  static func usbCommandReply(_ command: UInt8) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: SwitchProUSBHIDDescriptor.inputReportLength)
    report[0] = SwitchProUSBHIDDescriptor.usbCommandReplyReportID
    report[1] = command
    if command == 0x01 {
      report[3] = SwitchProUSBHIDDescriptor.proControllerDeviceType
      for (index, byte) in syntheticMAC.enumerated() { report[4 + index] = byte }
    }
    return report
  }

  static func subcommandAck(_ subcommand: UInt8, payload: [UInt8]) -> [UInt8] {
    var report = idleAck(subcommand)
    switch subcommand {
    case SwitchProUSBHIDDescriptor.requestDeviceInfoSubcommand:
      report[15] = 0x04
      report[16] = 0x00
      report[17] = SwitchProUSBHIDDescriptor.proControllerDeviceType
      for (index, byte) in syntheticMAC.enumerated() { report[19 + index] = byte }
    case SwitchProUSBHIDDescriptor.spiFlashReadSubcommand:
      let address = spiAddress(payload)
      let length = payload.count > 4 ? payload[4] : 0
      report[15] = UInt8(truncatingIfNeeded: address)
      report[16] = UInt8(truncatingIfNeeded: address >> 8)
      report[17] = UInt8(truncatingIfNeeded: address >> 16)
      report[18] = UInt8(truncatingIfNeeded: address >> 24)
      report[19] = length
      let data = spiFlashBytes(address: address, length: Int(length))
      for (index, byte) in data.enumerated() where 20 + index < report.count {
        report[20 + index] = byte
      }
    default:
      break
    }
    return report
  }

  private static func idleAck(_ subcommand: UInt8) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: SwitchProUSBHIDDescriptor.inputReportLength)
    report[0] = SwitchProUSBHIDDescriptor.subcommandAckReportID
    report[2] = SwitchProUSBHIDDescriptor.usbBatteryAndConnection
    writeStick(x: 0, y: 0, into: &report, at: 6)
    writeStick(x: 0, y: 0, into: &report, at: 9)
    report[13] = 0x80
    report[14] = subcommand
    return report
  }

  private static func spiAddress(_ payload: [UInt8]) -> UInt32 {
    guard payload.count >= 4 else { return 0 }
    return UInt32(payload[0])
      | UInt32(payload[1]) << 8
      | UInt32(payload[2]) << 16
      | UInt32(payload[3]) << 24
  }

  private static func spiFlashBytes(address: UInt32, length: Int) -> [UInt8] {
    let count = min(max(0, length), 32)
    var data = [UInt8](repeating: 0xFF, count: count)
    if address == 0x603D {
      let packed = factoryStickCalibration()
      for (index, byte) in packed.enumerated() where index < data.count { data[index] = byte }
    }
    return data
  }

  private static func factoryStickCalibration() -> [UInt8] {
    pack12(
      factoryExtent, factoryExtent, factoryCenter, factoryCenter, factoryExtent, factoryExtent
    )
      + pack12(
        factoryCenter, factoryCenter, factoryExtent, factoryExtent, factoryExtent, factoryExtent
      )
  }

  private static func pack12(
    _ a: UInt16,
    _ b: UInt16,
    _ c: UInt16,
    _ d: UInt16,
    _ e: UInt16,
    _ f: UInt16
  ) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 9)
    func write(_ first: UInt16, _ second: UInt16, at offset: Int) {
      bytes[offset] = UInt8(truncatingIfNeeded: first)
      bytes[offset + 1] = UInt8(truncatingIfNeeded: (first >> 8) | ((second & 0x0F) << 4))
      bytes[offset + 2] = UInt8(truncatingIfNeeded: second >> 4)
    }
    write(a, b, at: 0)
    write(c, d, at: 3)
    write(e, f, at: 6)
    return bytes
  }

  private static func stick12(_ value: Int16, invert: Bool) -> UInt16 {
    let polarity = invert ? (value == Int16.min ? Int16.max : -value) : value
    let scaled = Int(Self.stickCenter) + Int(polarity) * Self.stickExtent / 32_767
    return UInt16(max(0, min(4_095, scaled)))
  }

  private static func dpadBits(_ hat: GamepadHIDDescriptor.Hat) -> UInt32 {
    switch hat {
    case .neutral: 0
    case .north: 0x0002_0000
    case .northEast: 0x0006_0000
    case .east: 0x0004_0000
    case .southEast: 0x0005_0000
    case .south: 0x0001_0000
    case .southWest: 0x0009_0000
    case .west: 0x0008_0000
    case .northWest: 0x000A_0000
    }
  }

  private static func isSet(_ buttons: UInt32, bit: Int) -> Bool {
    ((buttons >> UInt32(bit)) & 1) != 0
  }
}
