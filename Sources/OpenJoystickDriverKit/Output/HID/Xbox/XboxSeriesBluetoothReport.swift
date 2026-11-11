import Foundation

/// HID report descriptor bytes for the `GameControllerCompatible` persona: the Xbox Series
/// controller over Bluetooth.
///
/// Consumers that know `045E:0B13` read report 1 at the bit positions of the real controller:
/// SDL's HIDAPI Xbox One Bluetooth driver and Firefox's `XboxSeriesXRemapper`. Apple's
/// GameController framework names every control, and delivers Home only to the frontmost app.
///
/// Reports:
/// - `0x01` (input, 16 bytes): left stick X/Y and right stick Z/Rz as `0...65535` with rest
///   `0x8000`, Brake (left trigger) and Accelerator (right trigger) as 10 bits each, a hat
///   `1...8` with null state 0 that alone carries the D-pad, 15 buttons, then Share as Consumer
///   Record (`0x0C:0xB2`). Guide is button 13; buttons 3, 6, 9 and 10 stay clear.
/// - `0x02` (input, 1 byte): Guide again, as System Main Menu (`0x01:0x85`), where GameController
///   reads Home.
/// - `0x03` (output, 8 bytes): actuator enable mask, then left trigger, right trigger, left and
///   right motor magnitudes `0...100`, duration, start delay and loop count.
/// - `0x04` (input): battery strength. OJD does not send it.
public enum XboxSeriesBluetoothHIDDescriptor {
  /// Report ID of the Guide input report.
  static let guideReportID: UInt8 = 0x02
  /// Report ID of the rumble output report.
  public static let rumbleReportID: UInt8 = 0x03
  /// Bytes of the rumble output report after its ID.
  static let rumbleReportPayloadSize = 8

  /// Maps stable OJD button bits to the button usages of report 1.
  ///
  /// The D-pad bits map to Button usage 0, which names no field, because the hat carries the
  /// D-pad.
  static let buttonUsageMap: [Int: Int] = [
    GamepadHIDDescriptor.ButtonBit.x.rawValue: 4,
    GamepadHIDDescriptor.ButtonBit.y.rawValue: 5,
    GamepadHIDDescriptor.ButtonBit.leftBumper.rawValue: 7,
    GamepadHIDDescriptor.ButtonBit.rightBumper.rawValue: 8,
    GamepadHIDDescriptor.ButtonBit.back.rawValue: 11,
    GamepadHIDDescriptor.ButtonBit.start.rawValue: 12,
    GamepadHIDDescriptor.ButtonBit.leftStick.rawValue: 14,
    GamepadHIDDescriptor.ButtonBit.rightStick.rawValue: 15,
    GamepadHIDDescriptor.ButtonBit.guide.rawValue: 13,
    GamepadHIDDescriptor.ButtonBit.dpadUp.rawValue: 0,
    GamepadHIDDescriptor.ButtonBit.dpadDown.rawValue: 0,
    GamepadHIDDescriptor.ButtonBit.dpadLeft.rawValue: 0,
    GamepadHIDDescriptor.ButtonBit.dpadRight.rawValue: 0,
  ]

  /// The right stick on Z/Rz, and the triggers on Simulation Brake (`0x02:0xC5`) and
  /// Accelerator (`0x02:0xC4`).
  static let axisUsageMap: [HIDAxisRole: HIDInputUsage] = [
    .leftStickX: HIDInputUsage(page: 0x01, usage: 0x30),
    .leftStickY: HIDInputUsage(page: 0x01, usage: 0x31),
    .rightStickX: HIDInputUsage(page: 0x01, usage: 0x32),
    .rightStickY: HIDInputUsage(page: 0x01, usage: 0x35),
    .leftTrigger: HIDInputUsage(page: 0x02, usage: 0xC5),
    .rightTrigger: HIDInputUsage(page: 0x02, usage: 0xC4),
  ]

  /// Share, which report 1 carries outside the Button page.
  static let digitalUsageMap: [Int: HIDInputUsage] = [
    GamepadHIDDescriptor.ButtonBit.share.rawValue: HIDInputUsage(page: 0x0C, usage: 0xB2)
  ]

  /// The report descriptor bytes.
  public static let descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x01, 0xA1, 0x00, 0x09, 0x30, 0x09, 0x31,
    0x15, 0x00, 0x27, 0xFF, 0xFF, 0x00, 0x00, 0x95, 0x02, 0x75, 0x10, 0x81, 0x02, 0xC0, 0x09, 0x01,
    0xA1, 0x00, 0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x27, 0xFF, 0xFF, 0x00, 0x00, 0x95, 0x02, 0x75,
    0x10, 0x81, 0x02, 0xC0, 0x05, 0x02, 0x09, 0xC5, 0x15, 0x00, 0x26, 0xFF, 0x03, 0x95, 0x01, 0x75,
    0x0A, 0x81, 0x02, 0x15, 0x00, 0x25, 0x00, 0x75, 0x06, 0x95, 0x01, 0x81, 0x03, 0x05, 0x02, 0x09,
    0xC4, 0x15, 0x00, 0x26, 0xFF, 0x03, 0x95, 0x01, 0x75, 0x0A, 0x81, 0x02, 0x15, 0x00, 0x25, 0x00,
    0x75, 0x06, 0x95, 0x01, 0x81, 0x03, 0x05, 0x01, 0x09, 0x39, 0x15, 0x01, 0x25, 0x08, 0x35, 0x00,
    0x46, 0x3B, 0x01, 0x66, 0x14, 0x00, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x75, 0x04, 0x95, 0x01,
    0x15, 0x00, 0x25, 0x00, 0x35, 0x00, 0x45, 0x00, 0x65, 0x00, 0x81, 0x03, 0x05, 0x09, 0x19, 0x01,
    0x29, 0x0F, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0F, 0x81, 0x02, 0x15, 0x00, 0x25, 0x00,
    0x75, 0x01, 0x95, 0x01, 0x81, 0x03,
    // Share: Consumer page, Record usage, after the button bytes.
    0x05, 0x0C, 0x0A, 0xB2, 0x00, 0x15, 0x00, 0x25, 0x01, 0x95, 0x01, 0x75, 0x01, 0x81, 0x02, 0x15,
    0x00, 0x25, 0x00, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03, 0x05, 0x01, 0x09, 0x80, 0x85, 0x02, 0xA1,
    0x00, 0x09, 0x85, 0x15, 0x00, 0x25, 0x01, 0x95, 0x01, 0x75, 0x01, 0x81, 0x02, 0x15, 0x00, 0x25,
    0x00, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03, 0xC0, 0x05, 0x0F, 0x09, 0x21, 0x85, 0x03, 0xA1, 0x02,
    0x09, 0x97, 0x15, 0x00, 0x25, 0x01, 0x75, 0x04, 0x95, 0x01, 0x91, 0x02, 0x15, 0x00, 0x25, 0x00,
    0x75, 0x04, 0x95, 0x01, 0x91, 0x03, 0x09, 0x70, 0x15, 0x00, 0x25, 0x64, 0x75, 0x08, 0x95, 0x04,
    0x91, 0x02, 0x09, 0x50, 0x66, 0x01, 0x10, 0x55, 0x0E, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
    0x95, 0x01, 0x91, 0x02, 0x09, 0xA7, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x01, 0x91,
    0x02, 0x65, 0x00, 0x55, 0x00, 0x09, 0x7C, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x01,
    0x91, 0x02, 0xC0, 0x85, 0x04, 0x05, 0x06, 0x09, 0x20, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08,
    0x95, 0x01, 0x81, 0x02, 0xC0,
  ]
}

/// The Xbox Series Bluetooth report layout of the `GameControllerCompatible` persona.
///
/// The hat carries the D-pad. The report has no slot for the touchpad click, microphone, paddles,
/// auxiliaries or touch controls.
public struct XboxSeriesBluetoothHIDReportFormat: VirtualGamepadReportFormat {
  /// The format that reads the descriptor and packs report 1.
  private let base: HIDDescriptorReportFormat

  /// The descriptor of the Xbox Series Bluetooth report.
  public var descriptor: [UInt8] { base.descriptor }
  /// The input report size without its ID.
  public var inputReportPayloadSize: Int { base.inputReportPayloadSize }
  /// The report ID of report 1.
  public var inputReportID: UInt8? { base.inputReportID }
  /// The rumble report size without its ID.
  public var outputReportPayloadSize: Int? { base.outputReportPayloadSize }
  /// The report ID of the rumble report.
  public var outputReportID: UInt8? { base.outputReportID }

  /// Creates the format.
  ///
  /// A descriptor that does not parse is a programming error and stops the process.
  public init() {
    do {
      base = try HIDDescriptorReportFormat(
        descriptor: XboxSeriesBluetoothHIDDescriptor.descriptor,
        outputReportID: XboxSeriesBluetoothHIDDescriptor.rumbleReportID,
        outputReportPayloadSize: XboxSeriesBluetoothHIDDescriptor.rumbleReportPayloadSize,
        buttonUsageMap: XboxSeriesBluetoothHIDDescriptor.buttonUsageMap,
        digitalUsageMap: XboxSeriesBluetoothHIDDescriptor.digitalUsageMap,
        axisUsageMap: XboxSeriesBluetoothHIDDescriptor.axisUsageMap
      )
    } catch {
      fatalError("[VirtualDevice] The Xbox Series Bluetooth descriptor does not parse: \(error)")
    }
  }

  /// Report 1 of `state`.
  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    base.buildInputReport(from: state)
  }

  /// Report 2, which carries Guide.
  public func buildAuxiliaryInputReports(from state: VirtualGamepadState) -> [[UInt8]] {
    let guide = state.buttons & (1 << UInt32(GamepadHIDDescriptor.ButtonBit.guide.rawValue)) != 0
    return [[XboxSeriesBluetoothHIDDescriptor.guideReportID, guide ? 1 : 0]]
  }
}
