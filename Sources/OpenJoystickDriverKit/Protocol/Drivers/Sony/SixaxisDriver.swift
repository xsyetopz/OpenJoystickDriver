public import Foundation

/// The report ID of the input report.
private let ds3InputReportID: UInt8 = 0x01
/// The length of the input report in bytes.
private let ds3InputReportLength = 49
/// The raw stick value at the center.
private let ds3AxisCenter: Float = 128
/// The largest distance above the center of a raw stick value.
private let ds3AxisPositiveMax: Float = 127
/// The largest distance below the center of a raw stick value.
private let ds3AxisNegativeMax: Float = 128
/// The maximum raw value of a trigger.
private let ds3TriggerMax: Float = 255
/// The ID of the first operational feature report.
private let ds3OperationalReportF2: UInt8 = 0xF2
/// The length of the first operational feature report in bytes.
private let ds3OperationalReportF2Length = 17
/// The ID of the second operational feature report.
private let ds3OperationalReportF5: UInt8 = 0xF5
/// The length of the second operational feature report in bytes.
private let ds3OperationalReportF5Length = 8
/// The report ID of the output report.
private let ds3OutputReportID: UInt8 = 0x01
/// The length of the output report in bytes.
private let ds3OutputReportLength = 49
/// The output report that the driver copies and fills in with the rumble and player LED bytes.
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

  /// The byte offsets of the input report.
  private enum ReportOffset {
    /// The offset of the report ID.
    static let reportID = 0
    /// The offset of the first button byte.
    static let buttons0 = 2
    /// The offset of the second button byte.
    static let buttons1 = 3
    /// The offset of the third button byte.
    static let buttons2 = 4
    /// The offset of the left stick's horizontal axis.
    static let leftX = 6
    /// The offset of the left stick's vertical axis.
    static let leftY = 7
    /// The offset of the right stick's horizontal axis.
    static let rightX = 8
    /// The offset of the right stick's vertical axis.
    static let rightY = 9
    /// The offset of the analog left trigger.
    static let l2Analog = 18
    /// The offset of the analog right trigger.
    static let r2Analog = 19
  }

  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The strength of the left rumble motor.
  private var physicalRumbleLeft: UInt8 = 0
  /// Whether the right rumble motor, which is on or off only, runs.
  private var physicalRumbleRightOn = false
  /// The player indicator of the next output report.
  private var physicalPlayerIndicator: PhysicalPlayerIndicator = .player1
  /// The bound variant: USB reads the operational feature reports.
  ///
  /// The Bluetooth enable report is a startup write in the controller's record.
  private let isBluetooth: Bool

  /// Creates the driver for the USB or the Bluetooth variant.
  public init(isBluetooth: Bool = false) { self.isBluetooth = isBluetooth }

  /// Clears the state of the session: neutral input.
  public func resetProtocolState() { state = .neutral }

  /// A Sixaxis lights no player LED until the host sets one.
  ///
  /// Over USB it ignores the LED report written right after the startup feature reads and takes it
  /// once it streams input. The description's USB variant sets the input timeout, because a USB
  /// Sixaxis streams while idle.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      assignsStartupPlayerIndicator: true,
      hidPlayerIndicatorFollowsFirstInput: true
    ).withDefaults(of: .sonySixaxis, variant: isBluetooth ? .bluetoothClassic : .usb)
  }

  /// Always nil: the report carries no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The controls of the description.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.sonySixaxis.describedControls
  }

  /// The rumble motors and the player indicator.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency, .highFrequency],
      lightingFeatures: [.playerIndicator],
      binaryRumbleMotors: [.highFrequency]
    )
  }

  /// No default colour: the controller has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// The operational feature reports that USB reads at startup; Bluetooth reads none.
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
  /// other's current value.
  ///
  /// The right motor is on/off only.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      physicalRumbleLeft = intensities.lowFrequency.byte
      physicalRumbleRightOn = intensities.highFrequency.byte > 0
    case .stopRumble:
      physicalRumbleLeft = 0
      physicalRumbleRightOn = false
    case .setPlayerIndicator(let indicator): physicalPlayerIndicator = indicator
    default: throw .unsupportedCapability(command.capability)
    }
    return PhysicalOutputPlan(writes: [.hidOutput(physicalOutputReport())])
  }

  /// Builds the output report from the current rumble state and player indicator.
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

  /// Decodes an input report; a short report, another report ID or a report with byte 1 equal to
  /// `0xFF` is ignored.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
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
      y: normalizeAxis(bytes[ReportOffset.leftY])
    )
    next.rightStick = StickPosition(
      x: normalizeAxis(bytes[ReportOffset.rightX]),
      y: normalizeAxis(bytes[ReportOffset.rightY])
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
  ) -> [(UInt8, UInt8, Control)] {
    [
      (b0, 0x01, .back), (b0, 0x02, .leftStickClick), (b0, 0x04, .rightStickClick),
      (b0, 0x08, .start), (b1, 0x01, .leftTrigger), (b1, 0x02, .rightTrigger),
      (b1, 0x04, .leftShoulder), (b1, 0x08, .rightShoulder), (b1, 0x10, .north),
      (b1, 0x20, .east), (b1, 0x40, .south), (b1, 0x80, .west), (b2, 0x01, .guide),
    ]
  }

  /// Scales a stick or trigger byte to -1...1 around the center.
  private func normalizeAxis(_ value: UInt8) -> Float {
    let centered = Float(value) - ds3AxisCenter
    let divisor = centered >= 0 ? ds3AxisPositiveMax : ds3AxisNegativeMax
    let normalized = centered / divisor
    return max(-1, min(1, normalized))
  }

  /// The hat direction of four D-pad flags.
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
