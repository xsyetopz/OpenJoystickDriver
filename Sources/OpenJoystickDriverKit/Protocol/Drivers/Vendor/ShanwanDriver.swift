import Foundation

private let shanwanMinimumReportLength = 19
private let shanwanAxisCenter: Float = 128
private let shanwanAxisPositiveMax: Float = 127
private let shanwanAxisNegativeMax: Float = 128
private let shanwanTriggerMax: Float = 255
/// A pressure byte counts as pressed once bit 7 is set, so light pressure and noise are ignored.
private let shanwanPressedThreshold: UInt8 = 0x80

/// Driver for Shanwan PS3-style pads in their "PS3/PC" USB mode, such as the Ant Esports GP100
/// (`2563:0575`, entered by holding Select + B while plugging in).
///
/// The offsets are for the report as macOS delivers it and byte 0 is not read. Sticks are at
/// bytes 3–6, per-button pressure at bytes 7–16 and analog triggers at bytes 17–18, the layout
/// SDL's `PS3ThirdParty` driver decodes. The descriptor's logical ranges do not match these
/// values, so the element-based fallback reports wrong axes. Face buttons, bumpers and the D-pad
/// are read from the pressure bytes, which a GP100 owner mapped on hardware (issue #38); the system
/// buttons use byte 1. Output is not driven: SDL disables output reports for Shanwan pads because
/// they can latch rumble on, and no GP100 rumble format has been confirmed in this mode.
public final class ShanwanDriver: PhysicalProtocolDriver {

  private enum ReportOffset {
    static let system: Int = 1
    static let leftStickX: Int = 3
    static let leftStickY: Int = 4
    static let rightStickX: Int = 5
    static let rightStickY: Int = 6
    static let dpadRight: Int = 7
    static let dpadLeft: Int = 8
    static let dpadUp: Int = 9
    static let dpadDown: Int = 10
    static let north: Int = 11
    static let east: Int = 12
    static let south: Int = 13
    static let west: Int = 14
    static let leftShoulder: Int = 15
    static let rightShoulder: Int = 16
    static let leftTrigger: Int = 17
    static let rightTrigger: Int = 18
  }

  private enum SystemMask {
    static let view: UInt8 = 0x01
    static let menu: UInt8 = 0x02
    static let leftStick: UInt8 = 0x04
    static let rightStick: UInt8 = 0x08
    static let guide: UInt8 = 0x10
  }

  private var state = ControllerState.neutral

  /// Creates a new ShanwanDriver.
  public init() {}

  /// A new transport session starts from neutral input.
  public func resetProtocolState() { state = .neutral }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: ControlID.xboxLayout.union([.guide]))
  }

  /// Decodes one Shanwan input report into the full controller state.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count >= shanwanMinimumReportLength else { return nil }

    var next = state
    // A pressure byte is zero at rest and rises while the control is held; only bit 7 counts.
    for (offset, control) in [
      (ReportOffset.south, ControlID.faceSouth), (ReportOffset.east, .faceEast),
      (ReportOffset.west, .faceWest), (ReportOffset.north, .faceNorth),
      (ReportOffset.leftShoulder, .leftShoulder), (ReportOffset.rightShoulder, .rightShoulder),
    ] { next.set(control, pressed: bytes[offset] & shanwanPressedThreshold != 0) }
    let system = bytes[ReportOffset.system]
    for (mask, control) in [
      (SystemMask.view, ControlID.view), (SystemMask.menu, .menu),
      (SystemMask.leftStick, .leftStickClick), (SystemMask.rightStick, .rightStickClick),
      (SystemMask.guide, .guide),
    ] { next.set(control, pressed: system & mask != 0) }
    next.hat = Self.direction(
      up: bytes[ReportOffset.dpadUp] & shanwanPressedThreshold != 0,
      right: bytes[ReportOffset.dpadRight] & shanwanPressedThreshold != 0,
      down: bytes[ReportOffset.dpadDown] & shanwanPressedThreshold != 0,
      left: bytes[ReportOffset.dpadLeft] & shanwanPressedThreshold != 0
    )
    next.leftTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.leftTrigger]) / shanwanTriggerMax
    )
    next.rightTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.rightTrigger]) / shanwanTriggerMax
    )
    next.leftStick = StickPosition(
      x: Self.axis(bytes[ReportOffset.leftStickX]),
      yDown: Self.axis(bytes[ReportOffset.leftStickY])
    )
    next.rightStick = StickPosition(
      x: Self.axis(bytes[ReportOffset.rightStickX]),
      yDown: Self.axis(bytes[ReportOffset.rightStickY])
    )
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// Converts one unsigned axis byte, centered on 128 with up and left low, to -1...1.
  static func axis(_ raw: UInt8) -> Float {
    let centered = Float(raw) - shanwanAxisCenter
    let divisor = centered >= 0 ? shanwanAxisPositiveMax : shanwanAxisNegativeMax
    return max(-1, min(1, centered / divisor))
  }

  /// Combines the four D-pad pressure flags; opposing directions cancel to neutral.
  private static func direction(up: Bool, right: Bool, down: Bool, left: Bool) -> HatDirection {
    switch (up && !down, right && !left, down && !up, left && !right) {
    case (true, false, false, false): .north
    case (true, true, false, false): .northEast
    case (false, true, false, false): .east
    case (false, true, true, false): .southEast
    case (false, false, true, false): .south
    case (false, false, true, true): .southWest
    case (false, false, false, true): .west
    case (true, false, false, true): .northWest
    default: .neutral
    }
  }
}
