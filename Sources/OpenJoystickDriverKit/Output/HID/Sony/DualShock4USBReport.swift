import Foundation

/// HID report descriptor and report layout of the `InControlCompatible` persona: the DualShock 4
/// v2 (`054C:09CC`) over USB.
///
/// macOS's `AppleGameControllerPersonality.kext` gives `054C:09CC` the `ps4` category, so the
/// GameController framework publishes it as a `GCDualShockGamepad` and reads report 1 at the byte
/// offsets of the genuine controller. Older Unity games that use InControl send rumble on macOS
/// only to a DualShock 4 over USB.
///
/// The descriptor is the one a genuine controller (USB, version `0x0100`) reports. Its reports:
/// - `0x01` (input, 63 bytes): left and right stick X/Y as `0...255` with rest `0x80`, a hat
///   `0...7` with null state 8, 14 buttons, a 6-bit counter, left and right trigger `0...255`, then
///   54 vendor bytes that hold the motion, battery and touchpad fields.
/// - `0x05` (output, 31 bytes): valid flags, then the right (weak) and left (strong) motor and the
///   lightbar color.
/// - feature reports, of which the persona answers `0x02`, `0x12`, `0x81` and `0xA3`: motion
///   calibration, pairing information, MAC address and firmware information. A request for any
///   other report fails as unsupported.
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
    0x02, 0x06, 0x00, 0xFF, 0x09, 0x20, 0x75, 0x06, 0x95, 0x01, 0x15, 0x00, 0x25, 0x7F, 0x81,
    0x02,
    // Left and right trigger on Rx/Ry.
    0x05, 0x01, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02,
    0x81, 0x02,
    // 54 vendor bytes: timestamp, temperature, gyro, accelerometer, battery and touchpad.
    0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02,
    // Output report 5 (31 bytes), then the feature reports the genuine controller declares.
    0x85, 0x05, 0x09, 0x22, 0x95, 0x1F, 0x91, 0x02, 0x85, 0x04, 0x09, 0x23, 0x95, 0x24, 0xB1,
    0x02, 0x85, 0x02, 0x09, 0x24, 0x95, 0x24, 0xB1, 0x02, 0x85, 0x08, 0x09, 0x25, 0x95, 0x03,
    0xB1, 0x02, 0x85, 0x10, 0x09, 0x26, 0x95, 0x04, 0xB1, 0x02, 0x85, 0x11, 0x09, 0x27, 0x95,
    0x02, 0xB1, 0x02, 0x85, 0x12, 0x06, 0x02, 0xFF, 0x09, 0x21, 0x95, 0x0F, 0xB1, 0x02, 0x85,
    0x13, 0x09, 0x22, 0x95, 0x16, 0xB1, 0x02, 0x85, 0x14, 0x06, 0x05, 0xFF, 0x09, 0x20, 0x95,
    0x10, 0xB1, 0x02, 0x85, 0x15, 0x09, 0x21, 0x95, 0x2C, 0xB1, 0x02, 0x06, 0x80, 0xFF, 0x85,
    0x80, 0x09, 0x20, 0x95, 0x06, 0xB1, 0x02, 0x85, 0x81, 0x09, 0x21, 0x95, 0x06, 0xB1, 0x02,
    0x85, 0x82, 0x09, 0x22, 0x95, 0x05, 0xB1, 0x02, 0x85, 0x83, 0x09, 0x23, 0x95, 0x01, 0xB1,
    0x02, 0x85, 0x84, 0x09, 0x24, 0x95, 0x04, 0xB1, 0x02, 0x85, 0x85, 0x09, 0x25, 0x95, 0x06,
    0xB1, 0x02, 0x85, 0x86, 0x09, 0x26, 0x95, 0x06, 0xB1, 0x02, 0x85, 0x87, 0x09, 0x27, 0x95,
    0x23, 0xB1, 0x02, 0x85, 0x88, 0x09, 0x28, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x89, 0x09, 0x29,
    0x95, 0x02, 0xB1, 0x02, 0x85, 0x90, 0x09, 0x30, 0x95, 0x05, 0xB1, 0x02, 0x85, 0x91, 0x09,
    0x31, 0x95, 0x03, 0xB1, 0x02, 0x85, 0x92, 0x09, 0x32, 0x95, 0x03, 0xB1, 0x02, 0x85, 0x93,
    0x09, 0x33, 0x95, 0x0C, 0xB1, 0x02, 0x85, 0x94, 0x09, 0x34, 0x95, 0x3F, 0xB1, 0x02, 0x85,
    0xA0, 0x09, 0x40, 0x95, 0x06, 0xB1, 0x02, 0x85, 0xA1, 0x09, 0x41, 0x95, 0x01, 0xB1, 0x02,
    0x85, 0xA2, 0x09, 0x42, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xA3, 0x09, 0x43, 0x95, 0x30, 0xB1,
    0x02, 0x85, 0xA4, 0x09, 0x44, 0x95, 0x0D, 0xB1, 0x02, 0x85, 0xF0, 0x09, 0x47, 0x95, 0x3F,
    0xB1, 0x02, 0x85, 0xF1, 0x09, 0x48, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xF2, 0x09, 0x49, 0x95,
    0x0F, 0xB1, 0x02, 0x85, 0xA7, 0x09, 0x4A, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xA8, 0x09, 0x4B,
    0x95, 0x01, 0xB1, 0x02, 0x85, 0xA9, 0x09, 0x4C, 0x95, 0x08, 0xB1, 0x02, 0x85, 0xAA, 0x09,
    0x4E, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xAB, 0x09, 0x4F, 0x95, 0x39, 0xB1, 0x02, 0x85, 0xAC,
    0x09, 0x50, 0x95, 0x39, 0xB1, 0x02, 0x85, 0xAD, 0x09, 0x51, 0x95, 0x0B, 0xB1, 0x02, 0x85,
    0xAE, 0x09, 0x52, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xAF, 0x09, 0x53, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0xB0, 0x09, 0x54, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xE0, 0x09, 0x57, 0x95, 0x02, 0xB1,
    0x02, 0x85, 0xB3, 0x09, 0x55, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xB4, 0x09, 0x55, 0x95, 0x3F,
    0xB1, 0x02, 0x85, 0xB5, 0x09, 0x56, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xD0, 0x09, 0x58, 0x95,
    0x3F, 0xB1, 0x02, 0x85, 0xD4, 0x09, 0x59, 0x95, 0x3F, 0xB1, 0x02, 0xC0,
  ]

  /// The MAC address the persona reports, least significant byte first, as reports 0x12 and 0x81
  /// carry it: `02:4F:4A:44:34:01`, a locally administered unicast address.
  static let macAddress: [UInt8] = [0x01, 0x34, 0x44, 0x4A, 0x4F, 0x02]

  /// Feature report 2, with ideal calibration in a genuine controller's layout.
  ///
  /// It holds zero gyro bias, gyro endpoints `±8_800` interleaved per axis as USB sends them, gyro
  /// speed `540 + 540`, accelerometer endpoints `±8_192` (one g), then the trailing `0x000C` a
  /// genuine controller sends. A genuine controller's endpoints are its own calibration.
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
    return report + [0x0C, 0x00]
  }()

  /// Feature report 0x12: the persona's MAC address, the fixed `08 25 00` link bytes, then a zero
  /// host address.
  static let pairingReport: [UInt8] =
    [pairingReportID] + macAddress + [0x08, 0x25, 0x00] + [UInt8](repeating: 0, count: 6)

  /// Feature report 0x81: the persona's MAC address.
  static let macAddressReport: [UInt8] = [macAddressReportID] + macAddress

  /// Feature report 0xA3, as a genuine controller sends it: build date `Sep 21 2018` and time
  /// `04:50:51` as 16-byte ASCII fields, then the version block, with hardware version `0xB40C`
  /// at byte 35 and firmware version `0xA00A` at byte 41, little-endian.
  static let firmwareReport: [UInt8] = {
    func field(_ text: String) -> [UInt8] {
      let bytes = Array(text.utf8)
      return bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
    }
    let versions: [UInt8] = [
      0x00, 0x01, 0x0C, 0xB4, 0x01, 0x00, 0x00, 0x00, 0x0A, 0xA0, 0x10, 0x20, 0x00, 0xA0, 0x02,
      0x00,
    ]
    return [firmwareReportID] + field("Sep 21 2018") + field("04:50:51") + versions
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
    /// The contact bytes of the two fingers in each of the three touch packets; bit 7 set means
    /// no touch.
    static let contacts = [34, 38, 43, 47, 52, 56]
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
    // A genuine controller at rest reports no touch packet and every contact lifted.
    for offset in Offset.contacts { data[offset] = Self.contactLifted }
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
