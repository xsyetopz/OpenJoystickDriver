import Foundation

/// USB DualShock 4 HID surface used by SDL HIDAPI PS4 and Apple GameController.
///
/// Input report `0x01` matches Linux hid-playstation / `DS4Parser` USB state:
/// sticks, packed hat and face buttons, shoulders, PS/touchpad, analog L2/R2.
/// Automatic selection uses this identity; live `GCController` / SDL binding needs
/// separate verification. Bluetooth CRC reports are out of scope.
public enum DualShock4USBHIDDescriptor {
  public static let reportID: UInt8 = 0x01
  public static let inputReportLength = 64
  public static let outputReportID: UInt8 = 0x05
  public static let outputReportLength = 32

  /// USB DualShock 4 HID report descriptor (gamepad collection): sticks as X/Y/Z/Rz,
  /// hat, 14 buttons, analog Rx/Ry triggers, 54-byte remainder, output report `0x05`.
  public static let descriptor: [UInt8] =
    [
      0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09,
      0x35, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02, 0x09, 0x39, 0x15,
      0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81,
      0x42, 0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0E, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01,
      0x95, 0x0E, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x20, 0x75, 0x06, 0x95, 0x01, 0x15, 0x00,
      0x25, 0x7F, 0x81, 0x02, 0x05, 0x01, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF, 0x00,
      0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02,
      0x85, 0x05, 0x09, 0x22, 0x95, 0x1F, 0x91, 0x02,
    ] + SonyUSBHostProtocol.featureDescriptor(dualSense: false) + [0xC0]
}

public struct DualShock4USBHIDReportFormat: VirtualGamepadReportFormat {
  public let supportsMotion = true
  public let descriptor: [UInt8] = DualShock4USBHIDDescriptor.descriptor
  public let inputReportPayloadSize: Int = DualShock4USBHIDDescriptor.inputReportLength - 1
  public let inputReportID: UInt8? = DualShock4USBHIDDescriptor.reportID
  public let outputReportPayloadSize: Int? = DualShock4USBHIDDescriptor.outputReportLength - 1
  public let outputReportID: UInt8? = DualShock4USBHIDDescriptor.outputReportID

  public init() {}

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: DualShock4USBHIDDescriptor.inputReportLength)
    report[0] = DualShock4USBHIDDescriptor.reportID
    report[1] = SonyHIDAxis.uint8(state.leftStickX)
    report[2] = SonyHIDAxis.uint8Inverted(state.leftStickY)
    report[3] = SonyHIDAxis.uint8(state.rightStickX)
    report[4] = SonyHIDAxis.uint8Inverted(state.rightStickY)
    report[5] = SonyHIDAxis.ds4Hat(state.hat) | SonyHIDAxis.ds4Face(state.buttons)
    report[6] = SonyHIDAxis.ds4Shoulders(
      state.buttons,
      leftTrigger: state.effectiveLeftTrigger,
      rightTrigger: state.effectiveRightTrigger
    )
    if SonyHIDAxis.isSet(state.buttons, bit: GamepadHIDDescriptor.ButtonBit.guide.rawValue) {
      report[7] |= 0x01
    }
    if state.touchpadPressed { report[7] |= 0x02 }
    // Only the touchpad button is modeled; both touch contacts are inactive.
    report[35] = 0x80
    report[39] = 0x80
    report[8] = SonyHIDAxis.triggerByte(state.effectiveLeftTrigger)
    report[9] = SonyHIDAxis.triggerByte(state.effectiveRightTrigger)
    let counter = UInt16(
      truncatingIfNeeded: VirtualMotionEncoding.ticks(
        nanoseconds: state.motionTimestampNanoseconds,
        numerator: 3,
        denominator: 16_000
      )
    )
    VirtualMotionEncoding.writeUnsigned(counter, into: &report, at: 10)
    VirtualMotionEncoding.writeSonyMotion(state, into: &report, at: 13)
    return report
  }
}

enum SonyHIDAxis {
  static func uint8(_ value: Int16) -> UInt8 { UInt8((Int(value) &+ 32_768) / 256) }

  static func uint8Inverted(_ value: Int16) -> UInt8 {
    uint8(value == Int16.min ? Int16.max : -value)
  }

  static func triggerByte(_ value: Int16) -> UInt8 {
    let clamped = max(0, min(32_767, Int(value)))
    return UInt8(clamped * 255 / 32_767)
  }

  static func isSet(_ buttons: UInt32, bit: Int) -> Bool { ((buttons >> UInt32(bit)) & 1) != 0 }

  static func ds4Hat(_ hat: GamepadHIDDescriptor.Hat) -> UInt8 {
    switch hat {
    case .neutral: 8
    case .north: 0
    case .northEast: 1
    case .east: 2
    case .southEast: 3
    case .south: 4
    case .southWest: 5
    case .west: 6
    case .northWest: 7
    }
  }

  static func ds4Face(_ buttons: UInt32) -> UInt8 {
    var bits: UInt8 = 0
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.x.rawValue) { bits |= 0x10 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.a.rawValue) { bits |= 0x20 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.b.rawValue) { bits |= 0x40 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.y.rawValue) { bits |= 0x80 }
    return bits
  }

  static func ds4Shoulders(_ buttons: UInt32, leftTrigger: Int16, rightTrigger: Int16) -> UInt8 {
    var bits: UInt8 = 0
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.leftBumper.rawValue) { bits |= 0x01 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.rightBumper.rawValue) { bits |= 0x02 }
    if leftTrigger > 0 { bits |= 0x04 }
    if rightTrigger > 0 { bits |= 0x08 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.back.rawValue)
      || isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.share.rawValue)
    {
      bits |= 0x10
    }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.start.rawValue) { bits |= 0x20 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.leftStick.rawValue) { bits |= 0x40 }
    if isSet(buttons, bit: GamepadHIDDescriptor.ButtonBit.rightStick.rawValue) { bits |= 0x80 }
    return bits
  }
}
