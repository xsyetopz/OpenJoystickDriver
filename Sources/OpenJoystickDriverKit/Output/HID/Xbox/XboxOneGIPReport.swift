import Foundation

/// HID report descriptor bytes for the `SDLCompatible` persona: Xbox One GIP packets carried as
/// numbered HID reports, and a copy of the state in the Xbox Bluetooth report for SDL2.
///
/// SDL 3 reads a device as Bluetooth only when the IOHID `Transport` starts with `Bluetooth`
/// (`src/hidapi/mac/hid.c` `hid_enumerate`, `SDL_hidapijoystick.c` `HIDAPI_AddDevice`). macOS
/// publishes every IOHIDUserDevice with transport `Virtual`, so SDL 3 parses every report as a GIP
/// packet (`SDL_hidapi_gip.c` `GIP_ReceivePacket`, or `SDL_hidapi_xboxone.c` when the GIP driver
/// is off): the report ID is the GIP command, then options, sequence and a length, then the data.
///
/// SDL 2 picks the parser by product ID instead (`SDL_hidapi_xboxone.c`
/// `HIDAPI_DriverXboxOne_InitDevice`, `SDL_IsJoystickBluetoothXboxOne`), and `0B0C` is on its
/// Bluetooth list, so it reads only Bluetooth report 1 and skips every other report ID. Each
/// parser skips the other's reports: SDL 2 ignores report IDs other than 1, 2 and 4, and SDL 3
/// drops report 1 as a GIP packet whose length runs past its end (see
/// ``XboxOneGIPHIDReportFormat/bluetoothStateReport(from:)``).
///
/// Reports:
/// - `0x20` (input): GIP input, options `0x00`, length 14, the 14-byte state data.
/// - `0x07` (input): GIP virtual key, options `0x20` (internal), length 2: bit 0 of the first
///   data byte is Guide, which SDL reads from no other report.
/// - `0x09` (output): GIP rumble, options `0x00`, length 9: sub-command `0x00`, activation mask,
///   left trigger, right trigger, left motor, right motor, duration, delay, repeat.
/// - `0x01` (input): the Xbox Series Bluetooth report 1 bytes, declared as vendor data so HID
///   clients that read usages see only report `0x20`'s controls.
/// - `0x02` (input): the Xbox Series Bluetooth Guide byte, as vendor data.
/// - `0x03` (output): the Xbox Series Bluetooth rumble report SDL 2 sends.
public enum XboxOneGIPHIDDescriptor {
  /// GIP command and report ID of the input state packet.
  public static let inputReportID: UInt8 = 0x20
  /// GIP command and report ID of the Guide button packet.
  public static let guideReportID: UInt8 = 0x07
  /// GIP command and report ID of the rumble packet.
  public static let rumbleReportID: UInt8 = 0x09

  /// GIP options of the input packet: no internal, acknowledge or chunk bit.
  static let inputOptions: UInt8 = 0x00
  /// GIP options of the virtual key packet: the internal bit.
  static let guideOptions: UInt8 = 0x20
  /// The input packet's data length, in the packet's one-byte length field.
  static let inputPayloadLength: UInt8 = 14
  /// The virtual key packet's data length: the Guide byte and the key code.
  static let guidePayloadLength: UInt8 = 2
  /// The key code that follows the Guide byte in a virtual key packet.
  static let guideKeyCode: UInt8 = 0x5B
  /// The sequence byte of the packets sent.
  ///
  /// SDL reads the sequence only to acknowledge or chunk packets, and neither option is set.
  static let sequence: UInt8 = 0x00

  /// Report 0x20 is the command, 3 more header bytes and the 14-byte state data.
  static let inputReportSize = 18

  /// Output report 0x09 is 12 bytes after its ID: options, sequence, length, sub-command and the
  /// 8-byte rumble body.
  static let rumbleReportPayloadSize = 12

  /// The report descriptor bytes.
  public static let descriptor: [UInt8] = [
    0x05, 0x01,  // Usage Page (Generic Desktop)
    0x09, 0x05,  // Usage (Game Pad)
    0xA1, 0x01,  // Collection (Application)

    // Report 0x20: GIP input.
    0x85, 0x20,  //   Report ID (0x20)
    0x06, 0x00, 0xFF,  //   Usage Page (Vendor Defined 0xFF00)
    0x09, 0x20,  //   Usage (0x20)
    0x75, 0x08, 0x95, 0x03,  //   Report Size (8), Report Count (3)
    0x81, 0x03,  //   Input (Constant, Variable): options, sequence, length
    0x75, 0x01, 0x95, 0x02,  //   Report Size (1), Report Count (2)
    0x81, 0x03,  //   Input (Constant): sync and reserved bits
    0x05, 0x09,  //   Usage Page (Button)
    0x09, 0x08, 0x09, 0x07, 0x09, 0x01, 0x09, 0x02, 0x09, 0x03, 0x09, 0x04,
    //   Start, Back, A, B, X, Y
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x06,  //   0...1, 1 bit, 6 fields
    0x81, 0x02,  //   Input (Data, Variable, Absolute)
    0x09, 0x0C, 0x09, 0x0D, 0x09, 0x0E, 0x09, 0x0F,  //   D-pad up, down, left, right
    0x09, 0x05, 0x09, 0x06, 0x09, 0x09, 0x09, 0x0A,  //   LB, RB, L3, R3
    0x95, 0x08,  //   Report Count (8)
    0x81, 0x02,  //   Input (Data, Variable, Absolute)
    0x05, 0x01,  //   Usage Page (Generic Desktop)
    0x09, 0x32,  //   Usage (Z): left trigger
    0x15, 0x00, 0x26, 0xFF, 0x03, 0x75, 0x0A, 0x95, 0x01,  //   0...1023, 10 bits
    0x81, 0x02,  //   Input (Data, Variable, Absolute)
    0x75, 0x06, 0x95, 0x01, 0x81, 0x03,  //   6 constant bits
    0x09, 0x35,  //   Usage (Rz): right trigger
    0x75, 0x0A, 0x95, 0x01, 0x81, 0x02,  //   10 bits
    0x75, 0x06, 0x95, 0x01, 0x81, 0x03,  //   6 constant bits
    0x09, 0x30, 0x09, 0x31, 0x09, 0x33, 0x09, 0x34,  //   X, Y, Rx, Ry
    0x16, 0x00, 0x80, 0x26, 0xFF, 0x7F,  //   -32768...32767
    0x75, 0x10, 0x95, 0x04,  //   Report Size (16), Report Count (4)
    0x81, 0x02,  //   Input (Data, Variable, Absolute)

    // Report 0x07: GIP virtual key.
    0x85, 0x07,  //   Report ID (0x07)
    0x06, 0x00, 0xFF,  //   Usage Page (Vendor Defined 0xFF00)
    0x09, 0x07,  //   Usage (0x07)
    0x75, 0x08, 0x95, 0x03,  //   Report Size (8), Report Count (3)
    0x81, 0x03,  //   Input (Constant): options, sequence, length
    0x05, 0x09,  //   Usage Page (Button)
    0x09, 0x0B,  //   Usage (Button 11): Guide
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01,  //   0...1, 1 bit
    0x81, 0x02,  //   Input (Data, Variable, Absolute)
    0x75, 0x01, 0x95, 0x07, 0x81, 0x03,  //   7 constant bits
    0x75, 0x08, 0x95, 0x01, 0x81, 0x03,  //   key code byte

    // Report 0x09: GIP rumble.
    0x85, 0x09,  //   Report ID (0x09)
    0x06, 0x00, 0xFF,  //   Usage Page (Vendor Defined 0xFF00)
    0x09, 0x09,  //   Usage (0x09)
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x0C,  //   0...255, 8 bits, 12 fields
    0x91, 0x02,  //   Output (Data, Variable, Absolute)

    // Report 0x01: Xbox Series Bluetooth state, 16 vendor bytes.
    0x85, 0x01,  //   Report ID (0x01)
    0x09, 0x01,  //   Usage (0x01)
    0x95, 0x10,  //   Report Count (16)
    0x81, 0x02,  //   Input (Data, Variable, Absolute)

    // Report 0x02: Xbox Series Bluetooth Guide, 1 vendor byte.
    0x85, 0x02,  //   Report ID (0x02)
    0x09, 0x02,  //   Usage (0x02)
    0x95, 0x01,  //   Report Count (1)
    0x81, 0x02,  //   Input (Data, Variable, Absolute)

    // Report 0x03: Xbox Series Bluetooth rumble, 8 vendor bytes.
    0x85, 0x03,  //   Report ID (0x03)
    0x09, 0x03,  //   Usage (0x03)
    0x95, 0x08,  //   Report Count (8)
    0x91, 0x02,  //   Output (Data, Variable, Absolute)
    0xC0,  // End Collection
  ]
}

/// The Xbox One GIP report layout of the 045E:0B0C `SDLCompatible` persona, with the state also
/// in the Xbox Series Bluetooth report that SDL 2 reads for that product ID.
///
/// The d-pad is four bits of the state data, not a hat. The data has no Share field, so this
/// persona carries neither Capture nor the touchpad click, microphone, paddles, auxiliaries or
/// touch controls. Sticks are signed 16-bit values; SDL reads both Y axes inverted, so the report
/// carries the bitwise complement of the state's Y.
public struct XboxOneGIPHIDReportFormat: VirtualGamepadReportFormat {
  /// The Xbox One GIP descriptor.
  public var descriptor: [UInt8] { XboxOneGIPHIDDescriptor.descriptor }
  /// The input report size without its ID.
  public var inputReportPayloadSize: Int { XboxOneGIPHIDDescriptor.inputReportSize - 1 }
  /// The report ID of the input state packet.
  public var inputReportID: UInt8? { XboxOneGIPHIDDescriptor.inputReportID }
  /// The rumble report size without its ID.
  public var outputReportPayloadSize: Int? { XboxOneGIPHIDDescriptor.rumbleReportPayloadSize }
  /// The report ID of the rumble packet.
  public var outputReportID: UInt8? { XboxOneGIPHIDDescriptor.rumbleReportID }

  /// The format that builds the Bluetooth reports SDL 2 reads.
  private let bluetooth = XboxSeriesBluetoothHIDReportFormat()

  /// Creates the format.
  public init() {}

  /// The GIP input state packet of `state`.
  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    func pressed(_ button: GamepadHIDDescriptor.ButtonBit) -> Bool {
      state.buttons & (1 << UInt32(button.rawValue)) != 0
    }
    func bits(_ flags: [(Bool, UInt8)]) -> UInt8 {
      flags.reduce(0) { $1.0 ? $0 | $1.1 : $0 }
    }
    let hat = state.hat
    let north = hat == .north || hat == .northEast || hat == .northWest
    let south = hat == .south || hat == .southEast || hat == .southWest
    let west = hat == .west || hat == .northWest || hat == .southWest
    let east = hat == .east || hat == .northEast || hat == .southEast

    let face = bits([
      (pressed(.start), 0x04), (pressed(.back), 0x08), (pressed(.a), 0x10), (pressed(.b), 0x20),
      (pressed(.x), 0x40), (pressed(.y), 0x80),
    ])
    let shoulders = bits([
      (north, 0x01), (south, 0x02), (west, 0x04), (east, 0x08), (pressed(.leftBumper), 0x10),
      (pressed(.rightBumper), 0x20), (pressed(.leftStick), 0x40), (pressed(.rightStick), 0x80),
    ])
    let leftTrigger = Self.triggerBytes(state.effectiveLeftTrigger)
    let rightTrigger = Self.triggerBytes(state.effectiveRightTrigger)
    let leftX = state.leftStickX.littleEndianBytes
    let leftY = (~state.leftStickY).littleEndianBytes
    let rightX = state.rightStickX.littleEndianBytes
    let rightY = (~state.rightStickY).littleEndianBytes
    return [
      XboxOneGIPHIDDescriptor.inputReportID, XboxOneGIPHIDDescriptor.inputOptions,
      XboxOneGIPHIDDescriptor.sequence, XboxOneGIPHIDDescriptor.inputPayloadLength,
      face, shoulders, leftTrigger.0, leftTrigger.1, rightTrigger.0, rightTrigger.1,
      leftX.0, leftX.1, leftY.0, leftY.1, rightX.0, rightX.1, rightY.0, rightY.1,
    ]
  }

  /// The GIP rumble report SDL 3 sends and the Bluetooth rumble report SDL 2 sends.
  public var outputReportIDs: Set<UInt8> {
    [XboxOneGIPHIDDescriptor.rumbleReportID, XboxSeriesBluetoothHIDDescriptor.rumbleReportID]
  }

  /// The virtual key packet that carries Guide, the only place SDL 3 reads it, then the Bluetooth
  /// state and Guide reports SDL 2 reads.
  public func buildAuxiliaryInputReports(from state: VirtualGamepadState) -> [[UInt8]] {
    let guide = state.buttons & (1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue)) != 0
    return [
      [
        XboxOneGIPHIDDescriptor.guideReportID, XboxOneGIPHIDDescriptor.guideOptions,
        XboxOneGIPHIDDescriptor.sequence, XboxOneGIPHIDDescriptor.guidePayloadLength,
        guide ? 1 : 0, XboxOneGIPHIDDescriptor.guideKeyCode,
      ],
      bluetoothStateReport(from: state),
    ] + bluetooth.buildAuxiliaryInputReports(from: state)
  }

  /// The Xbox Series Bluetooth report 1 of `state`, with the low bits of both left stick axes
  /// fixed so that SDL 3 drops the report.
  ///
  /// SDL 3 reads report 1 as a GIP packet (`SDL_hidapi_gip.c` `GIP_ReceivePacket`): byte 1, the
  /// low byte of left stick X, is its options, and byte 3, the low byte of left stick Y, starts
  /// its length. Options without the chunk bit `0x80` or an attachment index in bits `0...2`, and
  /// a one-byte length of at least 14, make a packet that claims more bytes than the 17 it has,
  /// and SDL drops it before it reads the command. Left stick X keeps 12 bits and Y keeps 11.
  func bluetoothStateReport(from state: VirtualGamepadState) -> [UInt8] {
    var report = bluetooth.buildInputReport(from: state)
    report[1] &= 0x78
    report[3] = report[3] & 0x70 | 0x0F
    return report
  }

  /// A 10-bit trigger value in two little-endian bytes: `0...Int16.max` scaled to `0...1023`.
  private static func triggerBytes(_ value: Int16) -> (UInt8, UInt8) {
    let scaled = UInt16(max(0, Int(value)) * 1023 / Int(Int16.max))
    return (UInt8(scaled & 0xFF), UInt8(scaled >> 8))
  }
}
