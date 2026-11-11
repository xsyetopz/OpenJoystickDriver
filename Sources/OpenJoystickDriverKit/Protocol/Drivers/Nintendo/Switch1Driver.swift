import Foundation

/// The report ID of the full input report.
private let switchProFullReportID: UInt8 = 0x30
/// The shortest full input report that is decoded.
private let switchProFullReportMinLength = 12
/// The raw value of a centered 12-bit stick axis.
private let switchProStickCenter: UInt16 = 2048
/// The largest distance of a raw stick axis from its center.
private let switchProStickMax: Float = 2047

/// The shape of the controller that the driver decodes.
public enum NintendoControllerLayout: Sendable {
  /// A Pro Controller.
  case pro
  /// A left Joy-Con.
  case leftJoyCon
  /// A right Joy-Con.
  case rightJoyCon
}

/// Driver for Nintendo Switch Pro Controller and Joy-Con full input reports.
///
/// Linux `hid-nintendo.c` uses report `0x30`, a packed 24-bit button field,
/// and two packed 12-bit stick fields. This experimental slice uses default
/// center calibration until physical hardware can verify SPI calibration reads.
public final class Switch1Driver: PhysicalProtocolDriver {

  /// The byte offsets of the full input report.
  private enum ReportOffset {
    /// The offset of the report ID.
    static let reportID = 0
    /// The offset of the packed 24-bit button field.
    static let buttons = 3
    /// The offset of the packed 12-bit left stick values.
    static let leftStick = 6
    /// The offset of the packed 12-bit right stick values.
    static let rightStick = 9
  }

  /// The shape of the controller that the driver decodes.
  public let layout: NintendoControllerLayout
  /// The bound variant: only a wired Pro Controller takes the USB setup commands, and Bluetooth
  /// startup reports need wider spacing.
  private let isBluetooth: Bool
  /// The decoder of motion samples.
  private var sensorSamples = NintendoSensorSamples()
  /// The calibration of motion samples; nominal until the calibration replies arrive.
  private var motionCalibration = NintendoMotionCalibration.nominal
  /// The SPI calibration reads whose reply has not arrived.
  private var pendingMotionCalibration: Set<SubcommandRequest.SPIRead.Purpose> = []
  /// The subcommand report, counter rule and startup requests from the family's description.
  private let subcommands: SubcommandPlan
  /// The 0x10 rumble-only report: the record's template, otherwise the description's.
  private let rumbleTemplate: RumbleOutputTemplate
  /// The factory motion calibration bytes read from SPI flash; nil until the reply arrives.
  private var factoryMotionBytes: [UInt8]?
  /// The user motion calibration bytes read from SPI flash; nil until a valid reply arrives.
  private var userMotionBytes: [UInt8]?
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The counter of the next output report.
  private var outputPacketNumber: UInt8 = 0
  /// The motor intensities of the last 0x10 rumble report, after each Joy-Con's side filter.
  private var lastRumble = RumbleIntensities.off
  /// The rumble bytes embedded in every subcommand report, from `SwitchProRumbleCodec`.
  ///
  /// A record's rumble template changes only the 0x10 report, not these.
  private var physicalRumbleData =
    SwitchProRumbleCodec.encode(intensity: 0) + SwitchProRumbleCodec.encode(intensity: 0)

  /// Creates a driver for a controller of `layout` on the USB or the Bluetooth variant.
  ///
  /// - Parameters:
  ///   - layout: The shape of the controller that the driver decodes.
  ///   - isBluetooth: Whether the controller runs on the Bluetooth variant instead of USB.
  ///   - rumbleTemplate: The record's rumble template; the description's when nil.
  public init(
    layout: NintendoControllerLayout = .pro,
    isBluetooth: Bool = false,
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.layout = layout
    self.isBluetooth = isBluetooth
    self.rumbleTemplate = PhysicalProtocolID.nintendoSwitch1.describedRumbleTemplate(
      variant: isBluetooth ? .bluetoothClassic : .usb,
      record: rumbleTemplate
    )
    // Loading refuses a NintendoSwitch1 description without subcommands, so the guard cannot
    // fail.
    guard let subcommands = PhysicalProtocolID.nintendoSwitch1.protocolDescription.subcommands
    else { fatalError("[ProtocolDescription] NintendoSwitch1 has no subcommands") }
    self.subcommands = subcommands
  }

  /// Clears the state of the session: neutral input and motion time re-anchored.
  public func resetProtocolState() {
    state = .neutral
    lastRumble = .off
    sensorSamples.reset()
  }

  /// The rumble motors of the layout (both on a Pro Controller, one on each Joy-Con) and the player
  /// indicator.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    let motors: [PhysicalRumbleMotor]
    switch layout {
    case .pro: motors = [.lowFrequency, .highFrequency]
    case .leftJoyCon: motors = [.lowFrequency]
    case .rightJoyCon: motors = [.highFrequency]
    }
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: motors,
      lightingFeatures: [.playerIndicator]
    )
  }

  /// No default colour: the controller has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// The session plan: startup recovery, the family description's defaults for the variant, and the
  /// rumble resend.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(hasStartupRecovery: true)
      .withDefaults(of: .nintendoSwitch1, variant: isBluetooth ? .bluetoothClassic : .usb)
      .withRumbleResend(of: rumbleTemplate)
  }

  /// The last rumble report again while a motor runs, when the template names a resend interval.
  ///
  /// It carries the session's next output counter value.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    rumbleTemplate.resendIntensities(after: lastRumble).map {
      [rumbleTemplate.write($0, counter: nextPacketNumber())]
    } ?? []
  }

  /// Always nil: the full report carries no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The controls of the layout, with digital triggers and motion.
  public var capabilities: ControllerCapabilities {
    let controls: Set<Control>
    switch layout {
    case .pro:
      controls = Control.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTrigger, .rightTrigger, .guide, .capture,
      ])
    case .leftJoyCon:
      controls = [
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .leftStickClick,
        .leftShoulder, .leftTrigger, .back,
        .capture, .auxiliary3, .auxiliary4,
      ]
    case .rightJoyCon:
      controls = [
        .south, .east, .west, .north, .rightStickX, .rightStickY, .rightStickClick,
        .rightShoulder, .rightTrigger, .start, .guide, .auxiliary5, .auxiliary6,
      ]
    }
    return ControllerCapabilities(
      controls: controls,
      digitalTriggers: controls.intersection([.leftTrigger, .rightTrigger]),
      motion: true
    )
  }

  /// The subcommand reports and calibration requests; the USB handshake commands are the
  /// description's startup writes.
  public func startupWrites() -> [PhysicalOutputWrite] {
    startupReports().map { .hidOutput($0) }
  }

  /// Each Joy-Con drives only its own side.
  ///
  /// The player subcommand repeats the last rumble and shares the rumble report's counter.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _): return rumblePlan(intensities)
    case .stopRumble: return rumblePlan(.off)
    case .setPlayerIndicator(let indicator):
      let player = subcommands.playerIndicator
      return PhysicalOutputPlan(writes: [
        .hidOutput(subcommand(player.subcommand, data: [player.pattern(for: indicator)]))
      ])
    default: throw .unsupportedCapability(command.capability)
    }
  }

  /// Plans the rumble report for `intensities`, silencing the side the layout does not have.
  private func rumblePlan(_ intensities: RumbleIntensities) -> PhysicalOutputPlan {
    let left = layout == .rightJoyCon ? UnipolarValue.min : intensities.lowFrequency
    let right = layout == .leftJoyCon ? UnipolarValue.min : intensities.highFrequency
    physicalRumbleData =
      SwitchProRumbleCodec.encode(intensity: left.byte)
      + SwitchProRumbleCodec.encode(intensity: right.byte)
    lastRumble = RumbleIntensities(lowFrequency: left, highFrequency: right)
    return PhysicalOutputPlan(writes: [
      rumbleTemplate.write(lastRumble, counter: nextPacketNumber())
    ])
  }

  /// Decodes one full `0x30` report; a `0x21` subcommand reply only feeds motion calibration.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    if bytes.first == 0x21 {
      consumeMotionCalibrationReply(bytes)
      return nil
    }
    guard bytes.count >= switchProFullReportMinLength,
      bytes[ReportOffset.reportID] == switchProFullReportID
    else { return nil }

    let buttonMask: UInt32
    switch layout {
    case .pro: buttonMask = 0x00FF_FFFF
    case .leftJoyCon: buttonMask = 0x00FF_2900
    case .rightJoyCon: buttonMask = 0x0000_16FF
    }
    let buttons = readUInt24LE(bytes, offset: ReportOffset.buttons) & buttonMask
    let left = readStick(bytes, offset: ReportOffset.leftStick)
    let right = readStick(bytes, offset: ReportOffset.rightStick)

    var next = state
    for (mask, control) in buttonTable { next.set(control, pressed: buttons & mask != 0) }
    next.hat = mapDpad(
      up: buttons & 0x0002_0000 != 0,
      right: buttons & 0x0004_0000 != 0,
      down: buttons & 0x0001_0000 != 0,
      left: buttons & 0x0008_0000 != 0
    )
    if layout != .rightJoyCon {
      next.leftStick = StickPosition(x: normalizeStick(left.x), y: -normalizeStick(left.y))
    }
    if layout != .leftJoyCon {
      next.rightStick = StickPosition(x: normalizeStick(right.x), y: -normalizeStick(right.y))
    }
    let motion = sensorSamples.decode(
      bytes,
      receivedAt: receivedAt.nanoseconds,
      layout: layout,
      calibration: motionCalibration
    )
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion)
  }

  /// Button masks and the Nintendo-label controls they report; SL and SR only on a Joy-Con.
  private var buttonTable: [(UInt32, Control)] {
    switch layout {
    case .pro: Self.proButtonTable
    case .leftJoyCon: Self.leftJoyConButtonTable
    case .rightJoyCon: Self.rightJoyConButtonTable
    }
  }

  /// The button masks of a Pro Controller.
  private static let proButtonTable: [(UInt32, Control)] = [
    (0x0000_0008, .east), (0x0000_0004, .south), (0x0000_0002, .north),
    (0x0000_0001, .west), (0x0040_0000, .leftShoulder), (0x0000_0040, .rightShoulder),
    (0x0080_0000, .leftTrigger), (0x0000_0080, .rightTrigger), (0x0000_0100, .back),
    (0x0000_0200, .start), (0x0000_0800, .leftStickClick), (0x0000_0400, .rightStickClick),
    (0x0000_1000, .guide), (0x0000_2000, .capture),
  ]
  /// The button masks of a left Joy-Con: its SL and SR followed by the Pro Controller's.
  private static let leftJoyConButtonTable: [(UInt32, Control)] =
    [(0x0020_0000, .auxiliary3), (0x0010_0000, .auxiliary4)] + proButtonTable
  /// The button masks of a right Joy-Con: its SL and SR followed by the Pro Controller's.
  private static let rightJoyConButtonTable: [(UInt32, Control)] =
    [(0x0000_0020, .auxiliary5), (0x0000_0010, .auxiliary6)] + proButtonTable

  /// Every request of the description in order; the SPI reads join the pending set.
  private func startupReports() -> [PhysicalHIDOutputReport] {
    pendingMotionCalibration = Set(subcommands.requests.compactMap { $0.spiRead?.purpose })
    factoryMotionBytes = nil
    userMotionBytes = nil
    return subcommands.requests.map { subcommand($0.subcommand, data: $0.data) }
  }

  /// The subcommand reports that re-request the SPI reads still pending.
  public func startupRecoveryWrites() -> [PhysicalOutputWrite] {
    pendingMotionCalibrationRequests().map { .hidOutput($0) }
  }

  /// The SPI reads whose reply has not arrived, in the description's order.
  private func pendingMotionCalibrationRequests() -> [PhysicalHIDOutputReport] {
    subcommands.requests
      .filter { $0.spiRead.map { pendingMotionCalibration.contains($0.purpose) } ?? false }
      .map { subcommand($0.subcommand, data: $0.data) }
  }

  /// Ends startup recovery: no SPI reply is awaited and the partial calibration bytes are dropped.
  public func expireStartupRecovery() {
    pendingMotionCalibration.removeAll()
    factoryMotionBytes = nil
    userMotionBytes = nil
  }

  /// Reads a `0x21` subcommand reply to an SPI calibration read; a short reply, an unknown request
  /// or a purpose that is not pending is ignored.
  ///
  /// The motion calibration is installed once the factory data has arrived.
  private func consumeMotionCalibrationReply(_ bytes: [UInt8]) {
    guard bytes.count >= 20, bytes[13] & 0x80 != 0 else { return }
    let address =
      UInt32(bytes[15]) | (UInt32(bytes[16]) << 8) | (UInt32(bytes[17]) << 16)
      | (UInt32(bytes[18]) << 24)
    guard
      let request = subcommands.requests.first(where: {
        $0.subcommand == bytes[14] && $0.spiRead?.address == address
      }),
      let read = request.spiRead, pendingMotionCalibration.contains(read.purpose)
    else { return }
    let length = Int(read.length)
    guard Int(bytes[19]) == length, bytes.count >= 20 + length else { return }
    let data = Array(bytes[20..<(20 + length)])
    if read.purpose == .factoryMotionCalibration {
      guard NintendoMotionCalibration.factory(data) != nil else { return }
      factoryMotionBytes = data
    } else {
      userMotionBytes = data[0] == 0xB2 && data[1] == 0xA1 ? data : nil
    }
    pendingMotionCalibration.remove(read.purpose)
    guard let factoryMotionBytes,
      let factory = NintendoMotionCalibration.factory(factoryMotionBytes)
    else { return }
    let calibrated =
      userMotionBytes.flatMap {
        NintendoMotionCalibration.factory(factoryMotionBytes, userOffsets: $0)
      } ?? factory
    motionCalibration = calibrated.installed(after: motionCalibration)
  }

  /// Builds the output report of subcommand `id` with `data`, carrying the next counter value and
  /// the current rumble bytes.
  private func subcommand(_ id: UInt8, data: [UInt8]) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: 11 + data.count)
    bytes[0] = subcommands.reportID
    bytes[1] = nextPacketNumber()
    bytes.replaceSubrange(2..<10, with: physicalRumbleData)
    bytes[10] = id
    for (index, value) in data.enumerated() { bytes[11 + index] = value }
    return PhysicalHIDOutputReport(reportID: subcommands.reportID, bytes: bytes)
  }

  /// Returns the current output counter value and advances it by the description's rule.
  private func nextPacketNumber() -> UInt8 {
    defer { outputPacketNumber = subcommands.nextCounter(after: outputPacketNumber) }
    return outputPacketNumber
  }

  /// Reads three bytes of `bytes` at `offset` as a little-endian number.
  private func readUInt24LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16)
  }

  /// Reads the two packed 12-bit stick values at `offset`.
  private func readStick(_ bytes: [UInt8], offset: Int) -> (x: UInt16, y: UInt16) {
    let x = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1] & 0x0F) << 8)
    let y = (UInt16(bytes[offset + 1]) >> 4) | (UInt16(bytes[offset + 2]) << 4)
    return (x, y)
  }

  /// Maps a raw 12-bit stick value to -1...1 around the center, clamped.
  private func normalizeStick(_ value: UInt16) -> Float {
    let centered = Float(Int(value) - Int(switchProStickCenter)) / switchProStickMax
    return max(-1, min(1, centered))
  }

  /// The hat direction of four D-pad flags; opposing directions cancel to neutral only through the
  /// neutral case.
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
