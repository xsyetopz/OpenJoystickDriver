import Foundation

private let xboxBluetoothInputReportID: UInt8 = 0x01
private let xboxBluetoothSystemReportID: UInt8 = 0x02
private let xboxBluetoothInputReportLength = 16
private let xboxBluetoothSystemReportLength = 2
private let xboxBluetoothAxisCenter: UInt16 = 0x7FFF
private let xboxBluetoothAxisSpan: Float = 32767
private let xboxBluetoothAxisDeadzone: Float = 0.08
private let xboxBluetoothTriggerMax: Float = 1023

/// Parser for Xbox controllers that present the Bluetooth HID profile.
///
/// This is the layout used by the Xbox One S and Series pads over Bluetooth,
/// and by third-party controllers that adopt the same identity. It differs
/// from the Xbox 360 wire protocol that ``Xbox360Parser`` handles: axes are
/// unsigned 16-bit centred at `0x7FFF` rather than signed, triggers are 10-bit,
/// and the Guide button arrives on its own report.
///
/// Reading the axes as signed, which the descriptor-driven fallback does, wraps
/// every value at or above `0x8000` to a negative number and confines both
/// sticks to a single quadrant.
public final class XboxBluetoothHIDParser: InputParser, @unchecked Sendable {

  private enum ReportOffset {
    static let leftStickX = 1
    static let leftStickY = 3
    static let rightStickX = 5
    static let rightStickY = 7
    static let leftTrigger = 9
    static let rightTrigger = 11
    static let hat = 13
    static let buttons = 14
    static let stickClicks = 15
  }

  private enum ButtonMask {
    static let a: UInt8 = 0x01
    static let b: UInt8 = 0x02
    static let x: UInt8 = 0x04
    static let y: UInt8 = 0x08
    static let leftBumper: UInt8 = 0x10
    static let rightBumper: UInt8 = 0x20
    static let back: UInt8 = 0x40
    static let start: UInt8 = 0x80
  }

  private enum StickClickMask {
    static let leftStick: UInt8 = 0x01
    static let rightStick: UInt8 = 0x02
  }

  private var prevButtons: UInt8 = 0
  private var prevStickClicks: UInt8 = 0
  private var prevHat: UInt8 = 0
  private var prevGuide = false
  private var prevLeftTrigger: UInt16 = 0
  private var prevRightTrigger: UInt16 = 0
  private var prevLeftX = xboxBluetoothAxisCenter
  private var prevLeftY = xboxBluetoothAxisCenter
  private var prevRightX = xboxBluetoothAxisCenter
  private var prevRightY = xboxBluetoothAxisCenter
  private let stateLock = NSLock()

  /// Creates a new XboxBluetoothHIDParser.
  public init() {}

  /// Parses one input report and returns zero or more controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = [UInt8](data)
    guard let reportID = bytes.first else { return [] }

    return stateLock.withLock {
      switch reportID {
      case xboxBluetoothSystemReportID: return guideEvents(bytes)
      case xboxBluetoothInputReportID: return inputEvents(bytes)
      default: return []
      }
    }
  }

  /// The Guide button is reported alone on the System Control collection, so a
  /// parser that only reads the main input report never observes it.
  private func guideEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    guard bytes.count >= xboxBluetoothSystemReportLength else { return [] }
    let isPressed = bytes[1] & 0x01 != 0
    guard isPressed != prevGuide else { return [] }
    prevGuide = isPressed
    return [isPressed ? .buttonPressed(.guide) : .buttonReleased(.guide)]
  }

  /// Decodes the main input report and records the state each field is
  /// compared against on the next report.
  private func inputEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    guard bytes.count >= xboxBluetoothInputReportLength else { return [] }
    var events: [ControllerEvent] = []
    events += buttonEvents(bytes[ReportOffset.buttons])
    events += stickClickEvents(bytes[ReportOffset.stickClicks])
    events += hatEvents(bytes[ReportOffset.hat])
    events += triggerEvents(bytes)
    events += stickEvents(bytes)
    prevButtons = bytes[ReportOffset.buttons]
    prevStickClicks = bytes[ReportOffset.stickClicks]
    prevHat = bytes[ReportOffset.hat]
    prevLeftTrigger = Self.trigger(bytes, at: ReportOffset.leftTrigger)
    prevRightTrigger = Self.trigger(bytes, at: ReportOffset.rightTrigger)
    prevLeftX = Self.rawAxis(bytes, at: ReportOffset.leftStickX)
    prevLeftY = Self.rawAxis(bytes, at: ReportOffset.leftStickY)
    prevRightX = Self.rawAxis(bytes, at: ReportOffset.rightStickX)
    prevRightY = Self.rawAxis(bytes, at: ReportOffset.rightStickY)
    return events
  }

  /// Maps the eight face, bumper and menu bits packed into byte 14.
  private func buttonEvents(_ value: UInt8) -> [ControllerEvent] {
    let pairs: [(UInt8, Button)] = [
      (ButtonMask.a, .a), (ButtonMask.b, .b), (ButtonMask.x, .x), (ButtonMask.y, .y),
      (ButtonMask.leftBumper, .leftBumper), (ButtonMask.rightBumper, .rightBumper),
      (ButtonMask.back, .back), (ButtonMask.start, .start),
    ]
    return pairs.flatMap {
      transition(mask: $0.0, current: value, previous: prevButtons, button: $0.1)
    }
  }

  /// Maps the two stick clicks, which sit in their own byte rather than
  /// alongside the other buttons.
  private func stickClickEvents(_ value: UInt8) -> [ControllerEvent] {
    let pairs: [(UInt8, Button)] = [
      (StickClickMask.leftStick, .leftStick), (StickClickMask.rightStick, .rightStick),
    ]
    return pairs.flatMap {
      transition(mask: $0.0, current: value, previous: prevStickClicks, button: $0.1)
    }
  }

  /// Emits a press or release only when the masked bit changed.
  private func transition(
    mask: UInt8,
    current: UInt8,
    previous: UInt8,
    button: Button
  ) -> [ControllerEvent] {
    let isPressed = current & mask != 0
    guard isPressed != (previous & mask != 0) else { return [] }
    return [isPressed ? .buttonPressed(button) : .buttonReleased(button)]
  }

  /// The D-pad is an eight-position hat, 1 = up and increasing clockwise.
  private func hatEvents(_ value: UInt8) -> [ControllerEvent] {
    guard value != prevHat else { return [] }
    return [.dpadChanged(Self.direction(for: value))]
  }

  /// Converts a hat value to a compass direction; anything outside 1...8 is neutral.
  private static func direction(for hat: UInt8) -> DpadDirection {
    switch hat {
    case 1: return .north
    case 2: return .northEast
    case 3: return .east
    case 4: return .southEast
    case 5: return .south
    case 6: return .southWest
    case 7: return .west
    case 8: return .northWest
    default: return .neutral
    }
  }

  /// Triggers are 10-bit values packed little-endian, so the high byte carries
  /// only the top two bits.
  private static func trigger(_ bytes: [UInt8], at index: Int) -> UInt16 {
    guard index + 1 < bytes.count else { return 0 }
    return (UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)) & 0x03FF
  }

  /// Emits a trigger event only when its 10-bit value changed.
  private func triggerEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let left = Self.trigger(bytes, at: ReportOffset.leftTrigger)
    let right = Self.trigger(bytes, at: ReportOffset.rightTrigger)
    if left != prevLeftTrigger {
      events.append(.leftTriggerChanged(Float(left) / xboxBluetoothTriggerMax))
    }
    if right != prevRightTrigger {
      events.append(.rightTriggerChanged(Float(right) / xboxBluetoothTriggerMax))
    }
    return events
  }

  /// Reads one little-endian axis word, defaulting to centre when the report
  /// is shorter than the offset.
  private static func rawAxis(_ bytes: [UInt8], at index: Int) -> UInt16 {
    guard index + 1 < bytes.count else { return xboxBluetoothAxisCenter }
    return UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
  }

  /// Converts one unsigned axis word to -1...1 about its `0x7FFF` centre.
  static func axis(_ raw: UInt16) -> Float {
    let offset = Float(Int(raw) - Int(xboxBluetoothAxisCenter))
    let normalized = max(-1, min(1, offset / xboxBluetoothAxisSpan))
    return abs(normalized) < xboxBluetoothAxisDeadzone ? 0 : normalized
  }

  /// Emits a stick event when either of its axes moved, so paired
  /// coordinates stay consistent.
  private func stickEvents(_ bytes: [UInt8]) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    let leftX = Self.rawAxis(bytes, at: ReportOffset.leftStickX)
    let leftY = Self.rawAxis(bytes, at: ReportOffset.leftStickY)
    if leftX != prevLeftX || leftY != prevLeftY {
      events.append(.leftStickChanged(x: Self.axis(leftX), y: Self.axis(leftY)))
    }
    let rightX = Self.rawAxis(bytes, at: ReportOffset.rightStickX)
    let rightY = Self.rawAxis(bytes, at: ReportOffset.rightStickY)
    if rightX != prevRightX || rightY != prevRightY {
      events.append(.rightStickChanged(x: Self.axis(rightX), y: Self.axis(rightY)))
    }
    return events
  }
}
