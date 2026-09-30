import Foundation

private let inputOnlyReportMinLength = 7
private let inputOnlyAxisCenter: Float = 128
private let inputOnlyAxisPositiveMax: Float = 127
private let inputOnlyAxisNegativeMax: Float = 128

/// Driver for wired Switch pads that expose only a fixed HID input report and accept no Switch
/// subcommands, such as the HORIPAD, PDP Faceoff and PowerA wired pads (catalog quirk
/// `input-only`).
///
/// The report has no report ID: two button bytes, a hat byte and four unsigned stick bytes
/// centered on 128 with up and left low, the layout SDL's `HandleInputOnlyControllerState`
/// decodes. ZL and ZR are digital. The pads take no output, so rumble and player lights are not
/// driven.
public final class SwitchInputOnlyDriver: PhysicalProtocolDriver {

  private enum ReportOffset {
    static let primaryButtons = 0
    static let systemButtons = 1
    static let hat = 2
    static let leftStickX = 3
    static let leftStickY = 4
    static let rightStickX = 5
    static let rightStickY = 6
  }

  /// Nintendo labels map by position: Y west, B south, A east, X north.
  private static let primaryButtons: [(UInt8, ControlID)] = [
    (0x01, .faceWest), (0x02, .faceSouth), (0x04, .faceEast), (0x08, .faceNorth),
    (0x10, .leftShoulder), (0x20, .rightShoulder), (0x40, .leftTriggerButton),
    (0x80, .rightTriggerButton),
  ]
  private static let systemButtons: [(UInt8, ControlID)] = [
    (0x01, .view), (0x02, .menu), (0x04, .leftStickClick), (0x08, .rightStickClick), (0x10, .guide),
    (0x20, .capture),
  ]
  private static let hatDirections: [HatDirection] = [
    .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
  ]

  private var state = ControllerState.neutral

  /// Creates a new SwitchInputOnlyDriver.
  public init() {}

  /// A new transport session starts from neutral input.
  public func resetProtocolState() { state = .neutral }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTriggerButton, .rightTriggerButton, .guide, .capture,
      ])
    )
  }

  /// Decodes one input report into the full controller state.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count >= inputOnlyReportMinLength else { return nil }

    var next = state
    let primary = bytes[ReportOffset.primaryButtons]
    for (mask, control) in Self.primaryButtons { next.set(control, pressed: primary & mask != 0) }
    let system = bytes[ReportOffset.systemButtons]
    for (mask, control) in Self.systemButtons { next.set(control, pressed: system & mask != 0) }
    let hat = Int(bytes[ReportOffset.hat])
    next.hat = hat < Self.hatDirections.count ? Self.hatDirections[hat] : .neutral
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
    let centered = Float(raw) - inputOnlyAxisCenter
    let divisor = centered >= 0 ? inputOnlyAxisPositiveMax : inputOnlyAxisNegativeMax
    return max(-1, min(1, centered / divisor))
  }
}
