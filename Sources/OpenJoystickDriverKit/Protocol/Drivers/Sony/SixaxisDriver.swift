import Foundation

private let ds3InputReportID: UInt8 = 0x01
private let ds3InputReportLength = 49
private let ds3AxisCenter: Float = 128
private let ds3AxisPositiveMax: Float = 127
private let ds3AxisNegativeMax: Float = 128
private let ds3TriggerMax: Float = 255
private let ds3OperationalReportF2: UInt8 = 0xF2
private let ds3OperationalReportF2Length = 17
private let ds3OperationalReportF5: UInt8 = 0xF5
private let ds3OperationalReportF5Length = 8
private let ds3OutputReportID: UInt8 = 0x01
private let ds3OutputReportLength = 49
private let ds3OutputReportTemplate: [UInt8] = [
  0x01, 0x01, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x27, 0x10, 0x00, 0x32,
  0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32, 0xFF, 0x27, 0x10, 0x00, 0x32, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00,
]

/// Driver for Sony DualShock 3 / SIXAXIS USB and Bluetooth input reports.
///
/// Linux `hid-sony.c` maps the DS3's button usages, sticks, and L2/R2 analog
/// usages. The native SIXAXIS descriptor uses report ID `0x01`, one reserved
/// byte, digital button bits including D-pad usages, four 8-bit stick axes,
/// and pressure axes later in the
/// 49-byte report. Physical rumble and player LEDs use the Linux `hid-sony.c` Sixaxis output
/// report contents, zero-padded to the descriptor's 48-byte output report plus its ID: over USB
/// on macOS the controller ignores the shorter 36-byte report. Sensors remain intentionally
/// omitted. The original Sixaxis (CECHZC1E) shares `054C:0268` with the DualShock 3 and has no
/// motors, so it ignores the rumble fields.
public final class SixaxisDriver: PhysicalProtocolDriver {

  private enum ReportOffset {
    static let reportID = 0
    static let buttons0 = 2
    static let buttons1 = 3
    static let buttons2 = 4
    static let leftX = 6
    static let leftY = 7
    static let rightX = 8
    static let rightY = 9
    static let l2Analog = 18
    static let r2Analog = 19
  }

  private var state = ControllerState.neutral
  private var physicalRumbleLeft: UInt8 = 0
  private var physicalRumbleRightOn = false
  private var physicalPlayerIndicator: PhysicalPlayerIndicator = .player1
  /// The bound variant: USB reads the operational feature reports. The Bluetooth enable report
  /// is a startup write in the controller's record.
  private let isBluetooth: Bool

  public init(isBluetooth: Bool = false) { self.isBluetooth = isBluetooth }

  /// A new transport session starts from neutral input.
  public func resetProtocolState() { state = .neutral }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.union([.guide, .leftTriggerButton, .rightTriggerButton])
    )
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain],
      lightingFeatures: [.playerIndicator],
      binaryRumbleMotors: [.rightMain]
    )
  }

  public var defaultColor: ControllerColor? { nil }

  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    guard !isBluetooth else { return [] }
    return [
      PhysicalHIDFeatureReadRequest(
        reportID: ds3OperationalReportF2,
        length: ds3OperationalReportF2Length
      ),
      PhysicalHIDFeatureReadRequest(
        reportID: ds3OperationalReportF5,
        length: ds3OperationalReportF5Length
      ),
    ]
  }

  /// One report carries both the rumble state and the player LED, so each command repeats the
  /// other's current value. The right motor is on/off only.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      physicalRumbleLeft = intensities.leftMain.byte
      physicalRumbleRightOn = intensities.rightMain.byte > 0
    case .stopRumble:
      physicalRumbleLeft = 0
      physicalRumbleRightOn = false
    case .setPlayerIndicator(let indicator): physicalPlayerIndicator = indicator
    default: throw .unsupportedCapability(command.capability)
    }
    return PhysicalOutputPlan(writes: [.hidOutput(physicalOutputReport())])
  }

  private func physicalOutputReport() -> PhysicalHIDOutputReport {
    var bytes = ds3OutputReportTemplate
    precondition(bytes.count == ds3OutputReportLength)
    bytes[3] = physicalRumbleRightOn ? 1 : 0
    bytes[5] = physicalRumbleLeft
    switch physicalPlayerIndicator {
    case .off: bytes[10] = 0x20
    case .player1: bytes[10] = 0x02
    case .player2: bytes[10] = 0x04
    case .player3: bytes[10] = 0x08
    case .player4: bytes[10] = 0x10
    }
    return PhysicalHIDOutputReport(reportID: ds3OutputReportID, bytes: bytes)
  }

  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    guard bytes.count >= ds3InputReportLength, bytes[ReportOffset.reportID] == ds3InputReportID,
      bytes[1] != 0xFF
    else { return nil }

    let b0 = bytes[ReportOffset.buttons0]
    var next = state
    for (byte, mask, control) in Self.buttonTable(
      b0,
      bytes[ReportOffset.buttons1],
      bytes[ReportOffset.buttons2]
    ) { next.set(control, pressed: byte & mask != 0) }
    next.hat = mapDpad(
      up: b0 & 0x10 != 0,
      right: b0 & 0x20 != 0,
      down: b0 & 0x40 != 0,
      left: b0 & 0x80 != 0
    )
    next.leftStick = StickPosition(
      x: normalizeAxis(bytes[ReportOffset.leftX]),
      yDown: normalizeAxis(bytes[ReportOffset.leftY])
    )
    next.rightStick = StickPosition(
      x: normalizeAxis(bytes[ReportOffset.rightX]),
      yDown: normalizeAxis(bytes[ReportOffset.rightY])
    )
    next.leftTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.l2Analog]) / ds3TriggerMax
    )
    next.rightTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.r2Analog]) / ds3TriggerMax
    )
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// Button bytes 0–2 with each mask and the standard-label control it reports.
  private static func buttonTable(
    _ b0: UInt8,
    _ b1: UInt8,
    _ b2: UInt8
  ) -> [(UInt8, UInt8, ControlID)] {
    [
      (b0, 0x01, .view), (b0, 0x02, .leftStickClick), (b0, 0x04, .rightStickClick),
      (b0, 0x08, .menu), (b1, 0x01, .leftTriggerButton), (b1, 0x02, .rightTriggerButton),
      (b1, 0x04, .leftShoulder), (b1, 0x08, .rightShoulder), (b1, 0x10, .faceNorth),
      (b1, 0x20, .faceEast), (b1, 0x40, .faceSouth), (b1, 0x80, .faceWest), (b2, 0x01, .guide),
    ]
  }

  private func normalizeAxis(_ value: UInt8) -> Float {
    let centered = Float(value) - ds3AxisCenter
    let divisor = centered >= 0 ? ds3AxisPositiveMax : ds3AxisNegativeMax
    let normalized = centered / divisor
    return max(-1, min(1, normalized))
  }

  private func mapDpad(up: Bool, right: Bool, down: Bool, left: Bool) -> HatDirection {
    switch (up, right, down, left) {
    case (true, false, false, false): return .north
    case (true, true, false, false): return .northEast
    case (false, true, false, false): return .east
    case (false, true, true, false): return .southEast
    case (false, false, true, false): return .south
    case (false, false, true, true): return .southWest
    case (false, false, false, true): return .west
    case (true, false, false, true): return .northWest
    default: return .neutral
    }
  }
}
