import Foundation

/// Decoder for gamepads whose controls are not described by a usable HID descriptor.
///
/// Many pads advertise a standard Gamepad collection and then extend it with a
/// vendor-defined usage page carrying the controls players actually use. The
/// descriptor-driven path cannot reach those: it subscribes to the Button and
/// Generic Desktop pages only, and the session subscribes to elements through
/// the driver's own declaration, so a vendor-page element is never observed.
///
/// This driver therefore reads raw input reports. ``sessionPlan`` leaves
/// `parsesHIDElementValues` false, which routes whole reports here instead of
/// decoded element values.
///
/// Report layout (byte 0 is the report ID, minimum 22 bytes):
/// ```
///   byte 0   : report ID
///   byte 1   : meta bitmask
///              bit 0  view (Select)
///              bit 1  menu (Start)
///              bit 2  leftStickClick (L3)
///              bit 3  rightStickClick (R3)
///   byte 2   : unused
///   byte 3   : left stick X  (0-255, center 127.5)
///   byte 4   : left stick Y  (0-255, center 127.5)
///   byte 5   : right stick X (0-255, center 127.5)
///   byte 6   : right stick Y (0-255, center 127.5)
///   byte 7   : hat right    (bit 7)
///   byte 8   : hat left     (bit 7)
///   byte 9   : hat up       (bit 7)
///   byte 10  : hat down     (bit 7)
///   byte 11  : face north (Y) (bit 7)
///   byte 12  : face east (B)  (bit 7)
///   byte 13  : face south (A) (bit 7)
///   byte 14  : face west (X)  (bit 7)
///   byte 15  : left shoulder  (bit 7)
///   byte 16  : right shoulder (bit 7)
///   byte 17  : left trigger  (0-255, 0 = released)
///   byte 18  : right trigger (0-255, 0 = released)
///   byte 19  : unused
///   byte 20  : unused
///   byte 21  : unused
/// ```
///
/// Axis sign is reported as the device sends it. Whether that sign matches the
/// player's expectation is a profile preference, not a device fact, so
/// inversion stays in profile axis tuning rather than here.
public final class ByteLayoutDriver: PhysicalProtocolDriver {
  private static let minimumReportLength = 22
  /// Half the travel of a stick axis, so byte 0 is -1 and byte 255 is +1.
  private static let stickCenter: Float = 127.5
  private static let stickSpan: Float = 127.5
  private static let triggerMax: Float = 255
  /// Resting noise inside this magnitude reports no movement.
  private static let deadzone: Float = 0.08

  /// One byte carries one control, active in bit 7, so each is diffed separately.
  private static let faceAndShoulderBytes: [(offset: Int, control: ControlID)] = [
    (11, .faceNorth), (12, .faceEast), (13, .faceSouth), (14, .faceWest), (15, .leftShoulder),
    (16, .rightShoulder),
  ]

  private static let metaBits: [(mask: UInt8, control: ControlID)] = [
    (0x01, .view), (0x02, .menu), (0x04, .leftStickClick), (0x08, .rightStickClick),
  ]

  /// Last snapshot emitted; a report decoding to the same state carries no event.
  private var state = ControllerState.neutral

  public init() {}

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: ControlID.xboxLayout.union([.guide]))
  }

  /// Reports are decoded here rather than through HID element values.
  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }

  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public func resetProtocolState() { state = .neutral }

  // MARK: - Input

  public func parse(report: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](report)
    guard bytes.count >= Self.minimumReportLength else { return nil }

    let next = decode(bytes)
    guard next != state else { return nil }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  private func decode(_ bytes: [UInt8]) -> ControllerState {
    var next = ControllerState.neutral

    for (mask, control) in Self.metaBits where bytes[1] & mask != 0 { next.pressed.insert(control) }
    for entry in Self.faceAndShoulderBytes where bytes[entry.offset] & 0x80 != 0 {
      next.pressed.insert(entry.control)
    }

    // Hat bytes are combined into a direction so diagonals survive.
    next.hat = Self.hatDirection(Self.hat(from: bytes))

    next.leftStick = StickPosition(
      x: Self.normalizeStick(bytes[3]),
      yDown: Self.normalizeStick(bytes[4])
    )
    next.rightStick = StickPosition(
      x: Self.normalizeStick(bytes[5]),
      yDown: Self.normalizeStick(bytes[6])
    )
    next.leftTrigger = UnipolarValue(normalized: Self.normalizeTrigger(bytes[17]))
    next.rightTrigger = UnipolarValue(normalized: Self.normalizeTrigger(bytes[18]))
    return next
  }

  /// Packs the four hat bytes into an index: 1 right, 2 left, 4 up, 8 down.
  private static func hat(from bytes: [UInt8]) -> UInt8 {
    (bytes[7] & 0x80 != 0 ? 1 : 0) | (bytes[8] & 0x80 != 0 ? 2 : 0) | (bytes[9] & 0x80 != 0 ? 4 : 0)
      | (bytes[10] & 0x80 != 0 ? 8 : 0)
  }

  private static func hatDirection(_ value: UInt8) -> HatDirection {
    switch value {
    case 0: .neutral
    case 4: .north
    case 4 | 1: .northEast
    case 1: .east
    case 8 | 1: .southEast
    case 8: .south
    case 8 | 2: .southWest
    case 2: .west
    case 4 | 2: .northWest
    default: .neutral
    }
  }

  // MARK: - Normalization

  private static func normalizeStick(_ raw: UInt8) -> Float {
    let normalized = (Float(raw) - stickCenter) / stickSpan
    let clamped = max(-1, min(1, normalized))
    return abs(clamped) < deadzone ? 0 : clamped
  }

  private static func normalizeTrigger(_ raw: UInt8) -> Float {
    min(1, max(0, Float(raw) / triggerMax))
  }
}
