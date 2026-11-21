import Foundation

/// HID report descriptor and report layout of the `InControlCompatible` persona: the DualShock 4
/// v2 (`054C:09CC`) over USB.
///
/// macOS's `AppleGameControllerPersonality.kext` gives `054C:09CC` the `ps4` category, so the
/// GameController framework publishes it as a `GCDualShockGamepad` and reads report 1 at the byte
/// offsets of the genuine controller. Older Unity games that use InControl send rumble on macOS
/// only to a DualShock 4 over USB.
///
/// The descriptor is hand-authored after the genuine layout and declares only the reports below:
/// - `0x01` (input, 63 bytes): left and right stick X/Y as `0...255` with rest `0x80`, a hat
///   `0...7` with null state 8, 14 buttons, a 6-bit counter, left and right trigger `0...255`, then
///   54 vendor bytes that hold the motion, battery and touchpad fields.
/// - `0x05` (output, 31 bytes): valid flags, then the right (weak) and left (strong) motor and the
///   lightbar color.
/// - `0x02`, `0x12`, `0x81` and `0xA3` (feature): motion calibration, pairing information, MAC
///   address and firmware information.
public enum DualShock4USBHIDDescriptor {
  /// Report ID of the input report.
  static let inputReportID: UInt8 = 0x01
  /// Bytes of the input report after its ID.
  static let inputReportPayloadSize = 63
  /// Report ID of the rumble and lightbar output report.
  public static let outputReportID: UInt8 = 0x05
  /// Bytes of the output report after its ID.
  static let outputReportPayloadSize = 31

  /// Report ID of the motion calibration feature report.
  static let calibrationReportID: UInt8 = 0x02
  /// Report ID of the pairing information feature report.
  static let pairingReportID: UInt8 = 0x12
  /// Report ID of the MAC address feature report.
  static let macAddressReportID: UInt8 = 0x81
  /// Report ID of the firmware information feature report.
  static let firmwareReportID: UInt8 = 0xA3

  /// The report descriptor bytes.
  public static let descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01,
    // Left stick X/Y and right stick Z/Rz, one byte each.
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
    0x95, 0x04, 0x81, 0x02,
    // The hat, 0...7 clockwise from north, with null state.
    0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04,
    0x95, 0x01, 0x81, 0x42, 0x65, 0x00,
    // 14 buttons, then the 6-bit report counter.
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0E, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0E, 0x81,
    0x02, 0x06, 0x00, 0xFF, 0x09, 0x20, 0x75, 0x06, 0x95, 0x01, 0x15, 0x00, 0x25, 0x3F, 0x81,
    0x02,
    // Left and right trigger on Rx/Ry.
    0x05, 0x01, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02,
    0x81, 0x02,
    // 54 vendor bytes: timestamp, temperature, gyro, accelerometer, battery and touchpad.
    0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02,
    // Output report 5, 31 bytes.
    0x85, 0x05, 0x09, 0x22, 0x95, 0x1F, 0x91, 0x02,
    // Feature report 2, 36 bytes of motion calibration.
    0x85, 0x02, 0x09, 0x24, 0x95, 0x24, 0xB1, 0x02,
    // Feature report 0x12, 15 bytes of pairing information.
    0x85, 0x12, 0x06, 0x02, 0xFF, 0x09, 0x21, 0x95, 0x0F, 0xB1, 0x02,
    // Feature report 0x81, the 6-byte MAC address.
    0x06, 0x80, 0xFF, 0x85, 0x81, 0x09, 0x21, 0x95, 0x06, 0xB1, 0x02,
    // Feature report 0xA3, 48 bytes of firmware information.
    0x85, 0xA3, 0x09, 0x25, 0x95, 0x30, 0xB1, 0x02,
    0xC0,
  ]

  /// The MAC address the persona reports, least significant byte first, as reports 0x12 and 0x81
  /// carry it: `02:4F:4A:44:34:01`, a locally administered unicast address.
  static let macAddress: [UInt8] = [0x01, 0x34, 0x44, 0x4A, 0x4F, 0x02]

  /// Feature report 2: zero gyro bias, gyro endpoints `±8_800` interleaved per axis as USB sends
  /// them, gyro speed `540 + 540`, and accelerometer endpoints `±8_192` (one g).
  static let calibrationReport: [UInt8] = {
    let values: [Int16] = [
      0, 0, 0, 8_800, -8_800, 8_800, -8_800, 8_800, -8_800, 540, 540, 8_192, -8_192, 8_192,
      -8_192, 8_192, -8_192,
    ]
    var report = [calibrationReportID]
    for value in values {
      let bits = UInt16(bitPattern: value)
      report += [UInt8(bits & 0xFF), UInt8(bits >> 8)]
    }
    return report + [0, 0]
  }()

  /// Feature report 0x12: the persona's MAC address, the fixed `08 25 00` link bytes, then a zero
  /// host address.
  static let pairingReport: [UInt8] =
    [pairingReportID] + macAddress + [0x08, 0x25, 0x00] + [UInt8](repeating: 0, count: 6)

  /// Feature report 0x81: the persona's MAC address.
  static let macAddressReport: [UInt8] = [macAddressReportID] + macAddress

  /// Feature report 0xA3: build date and time as 16-byte ASCII fields, then hardware version
  /// `0x0100` at byte 35 and firmware version `0x0100` at byte 41.
  static let firmwareReport: [UInt8] = {
    func field(_ text: String) -> [UInt8] {
      let bytes = Array(text.utf8)
      return bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
    }
    var report = [firmwareReportID] + field("Jan 01 2026") + field("00:00:00")
    report += [UInt8](repeating: 0, count: 49 - report.count)
    report[35] = 0x00
    report[36] = 0x01
    report[41] = 0x00
    report[42] = 0x01
    return report
  }()
}

/// The DualShock 4 USB report layout of the `InControlCompatible` persona.
///
/// The hat carries the D-pad, Share is `back` and Options is `start`. The report carries no
/// touchpad click, touch or motion: the touchpad reads untouched and the gyro and accelerometer
/// read zero. The battery reads full on wired power.
public struct DualShock4USBHIDReportFormat: VirtualGamepadReportFormat {
  /// The descriptor of the DualShock 4 USB report.
  public let descriptor = DualShock4USBHIDDescriptor.descriptor
  /// The input report size without its ID.
  public let inputReportPayloadSize = DualShock4USBHIDDescriptor.inputReportPayloadSize
  /// The report ID of report 1.
  public let inputReportID: UInt8? = DualShock4USBHIDDescriptor.inputReportID
  /// The output report size without its ID.
  public let outputReportPayloadSize: Int? = DualShock4USBHIDDescriptor.outputReportPayloadSize
  /// The report ID of the output report.
  public let outputReportID: UInt8? = DualShock4USBHIDDescriptor.outputReportID
  /// The calibration, pairing, MAC address and firmware feature reports.
  public let featureReports: [UInt8: [UInt8]] = [
    DualShock4USBHIDDescriptor.calibrationReportID: DualShock4USBHIDDescriptor.calibrationReport,
    DualShock4USBHIDDescriptor.pairingReportID: DualShock4USBHIDDescriptor.pairingReport,
    DualShock4USBHIDDescriptor.macAddressReportID: DualShock4USBHIDDescriptor.macAddressReport,
    DualShock4USBHIDDescriptor.firmwareReportID: DualShock4USBHIDDescriptor.firmwareReport,
  ]

  /// The data offsets of report 1 after its ID.
  private enum Offset {
    /// The first button byte: the hat nibble, then Square, Cross, Circle and Triangle.
    static let buttons0 = 4
    /// The second button byte: L1, R1, L2, R2, Share, Options, L3 and R3.
    static let buttons1 = 5
    /// The third button byte: PS, the touchpad click, then the counter.
    static let buttons2 = 6
    /// The left trigger.
    static let leftTrigger = 7
    /// The right trigger.
    static let rightTrigger = 8
    /// The battery level and the wired-power bit.
    static let power = 29
    /// The number of touch packets.
    static let touchPackets = 32
    /// The contact byte of the first finger; bit 7 set means no touch.
    static let firstContact = 34
    /// The contact byte of the second finger.
    static let secondContact = 38
  }

  /// The battery byte: level 11 (full) with the wired-power bit.
  private static let fullOnWiredPower: UInt8 = 0x1B
  /// The contact byte bit that marks a finger as lifted.
  private static let contactLifted: UInt8 = 0x80
  /// The null state of the hat nibble.
  private static let hatNeutral: UInt8 = 8

  /// Data byte, mask and OJD button bit of each button.
  private static let buttonTable: [(offset: Int, mask: UInt8, bit: Int)] = [
    (Offset.buttons0, 0x10, GamepadHIDDescriptor.ButtonBit.x),
    (Offset.buttons0, 0x20, .a), (Offset.buttons0, 0x40, .b), (Offset.buttons0, 0x80, .y),
    (Offset.buttons1, 0x01, .leftBumper), (Offset.buttons1, 0x02, .rightBumper),
    (Offset.buttons1, 0x10, .back), (Offset.buttons1, 0x20, .start),
    (Offset.buttons1, 0x40, .leftStick), (Offset.buttons1, 0x80, .rightStick),
    (Offset.buttons2, 0x01, .guide),
  ].map { ($0.0, $0.1, $0.2.rawValue) }

  /// Creates the format.
  public init() {}

  /// Report 1 of `state`.
  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: inputReportPayloadSize)
    data[0] = Self.stickByte(state.leftStickX)
    data[1] = Self.stickByte(state.leftStickY)
    data[2] = Self.stickByte(state.rightStickX)
    data[3] = Self.stickByte(state.rightStickY)
    data[Offset.buttons0] =
      state.hat == .neutral ? Self.hatNeutral : state.hat.rawValue - 1
    for (offset, mask, bit) in Self.buttonTable where state.buttons & (1 << UInt32(bit)) != 0 {
      data[offset] |= mask
    }
    let leftTrigger = Self.triggerByte(state.effectiveLeftTrigger)
    let rightTrigger = Self.triggerByte(state.effectiveRightTrigger)
    if leftTrigger > 0 { data[Offset.buttons1] |= 0x04 }
    if rightTrigger > 0 { data[Offset.buttons1] |= 0x08 }
    data[Offset.leftTrigger] = leftTrigger
    data[Offset.rightTrigger] = rightTrigger
    data[Offset.power] = Self.fullOnWiredPower
    data[Offset.touchPackets] = 1
    data[Offset.firstContact] = Self.contactLifted
    data[Offset.secondContact] = Self.contactLifted
    return [DualShock4USBHIDDescriptor.inputReportID] + data
  }

  /// The `0...255` stick byte of a signed 16-bit axis, rest at `0x80`.
  private static func stickByte(_ value: Int16) -> UInt8 {
    UInt8((Int(value) + 32_768) >> 8)
  }

  /// The `0...255` trigger byte of a `0...Int16.max` trigger.
  private static func triggerByte(_ value: Int16) -> UInt8 {
    UInt8(Int(max(value, 0)) * 255 / Int(Int16.max))
  }
}
