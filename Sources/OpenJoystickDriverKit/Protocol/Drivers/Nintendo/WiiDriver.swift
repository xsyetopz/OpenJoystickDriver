import Foundation

/// Driver for the Wii Remote over Bluetooth HID: core buttons, the accelerometer, status and
/// battery, with the memory exchanges that read the accelerometer calibration and run the
/// extension handshake.
///
/// The report layouts, the button and accelerometer bits, the report-mode choice and the register
/// scripts come from the `wiiRemote` field of `nintendo-wii.json`. Facts are from WiiBrew's
/// Wiimote page. Nunchuk, Classic and Motion Plus data and the remote's motion sample are
/// decoded; IR, the speaker, LEDs and rumble are not decoded or written yet.
public final class WiiDriver: PhysicalProtocolDriver {
  /// The input report that answers a status request and carries the battery.
  static let statusReportID: UInt8 = 0x20
  /// The input report that answers a memory read.
  static let memoryReplyReportID: UInt8 = 0x21
  /// The input report that acknowledges an output report.
  static let acknowledgementReportID: UInt8 = 0x22
  /// The output report that writes memory.
  static let memoryWriteOutputID: UInt8 = 0x16
  /// The output report that reads memory.
  static let memoryReadOutputID: UInt8 = 0x17
  /// The flag of a memory output report that addresses the control registers; the EEPROM, whose
  /// addresses fit 16 bits, has it clear.
  static let registerSpaceFlag: UInt8 = 0x04
  /// The output report that sets the data reporting mode.
  private static let reportModeOutputID: UInt8 = 0x12
  /// The output report that requests a status report.
  private static let statusRequestOutputID: UInt8 = 0x15
  /// The bit of the status flags that reports an extension.
  private static let extensionBit: UInt8 = 0x02
  /// The bit of the first data byte of the mode report that makes the remote report on every
  /// cycle, not only on a change.
  private static let continuousBit: UInt8 = 0x04
  /// The bit of the status flags that reports a low battery.
  private static let batteryLowBit: UInt8 = 0x01
  /// The battery byte of a full battery; the byte counts in 1/200 of full.
  private static let batteryFull = 200

  /// A raw accelerometer reading of the remote; each axis has 10 bits.
  struct RawAcceleration: Equatable {
    /// The X axis.
    let x: Int
    /// The Y axis.
    let y: Int
    /// The Z axis.
    let z: Int
  }

  /// The family's `wiiRemote` description.
  let wii: ProtocolDescription.WiiRemote
  /// The wait for the reply to a memory read or write, in nanoseconds.
  let replyTimeoutNanoseconds: UInt64
  /// The state after the latest report.
  var state = ControllerState.neutral
  /// The features the driver asks the report mode to carry; a decoded extension adds its own.
  var requestedFeatures: Set<ProtocolDescription.WiiRemote.BlockKind> = [.accelerometer]
  /// The writes that parsing queued, until the pipeline drains them.
  var pendingWrites: [PhysicalOutputWrite] = []
  /// The memory exchanges of the session; the first one is on the wire.
  var exchanges: [Exchange] = []
  /// Whether the latest status report showed an extension.
  var isExtensionPlugged = false
  /// Whether the session has queued the calibration read.
  var hasRequestedCalibration = false
  /// The extension the handshake identified; nil while none is plugged or it is unread.
  var extensionKind: ExtensionKind?
  /// The accelerometer calibration read from the remote; nil until read, and when the remote
  /// returns a block whose gravity equals its zero point (uncalibrated).
  var accelerometerCalibration: AccelerometerCalibration?
  /// The raw center of each extension stick, taken from the first sample after the handshake.
  var extensionCenters: [Control: Int] = [:]
  /// The latest Motion Plus gyro frame; nil while none is active.
  var gyro: RawGyro?
  /// The still-window sums of the gyro rest offset and its result (`GyroRestOffset`).
  var gyroRest = GyroRest()
  /// Whether the driver activated Motion Plus in this session and the port has not shown another
  /// kind since; the handshake would switch it off, so only its ID is read again.
  var motionPlusActive = false
  /// The Nunchuk or Classic kind the handshake last identified; the passthrough mode follows it.
  var passthroughBase: String?
  /// The index of the next motion sample in the session.
  var motionSequence: UInt64 = 0
  /// The latest exchange that ended in a failure; the driver does not retry it.
  var failure: ExchangeFailure?
  /// The latest memory reply the driver refused.
  var refusedReply: ReplyRefusal?
  /// The latest power facts from a status report.
  public private(set) var power: ControllerConnectionState.Power?
  /// Whether the latest status report set the low-battery flag.
  public private(set) var isBatteryLow = false
  /// Whether the gyro rest offset is measured (`GyroRestOffset`: calibrating until then).
  public var isGyroRestReady: Bool { gyroRest.offset != nil }
  /// The accelerometer reading of the latest report that carried one.
  private(set) var acceleration: RawAcceleration?

  /// Creates the driver for the family's description.
  public init(tuning: ControllerTuning? = nil) {
    guard let wii = PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote else {
      preconditionFailure("nintendo-wii.json describes no wiiRemote field")
    }
    self.wii = wii
    replyTimeoutNanoseconds =
      UInt64(PhysicalProtocolID.nintendoWii.described(\.replyTimeoutMilliseconds, in: tuning))
      * 1_000_000
  }

  /// The core buttons, every control an extension layout drives, and motion.
  ///
  /// The set does not change with the plugged extension.
  public var capabilities: ControllerCapabilities {
    let extensionControls = wii.extensions.compactMap(\.layout).flatMap {
      $0.buttons.map(\.control) + $0.sticks.map(\.control) + $0.triggers.map(\.control)
    }
    return ControllerCapabilities(
      controls: Set(wii.coreButtons.map(\.control) + extensionControls),
      motion: true
    )
  }

  /// The session of the description's Bluetooth variant.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan().withDefaults(of: .nintendoWii, variant: .bluetoothClassic)
  }

  /// No output yet.
  public var outputCapabilities: PhysicalControllerOutputCapabilities { .none }

  /// No colour: the remote has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// Always nil: the report carries no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Clears the state of the session: neutral input, no reading, no extension, no calibration and
  /// no exchange.
  public func resetProtocolState() {
    state = .neutral
    acceleration = nil
    pendingWrites = []
    exchanges = []
    isExtensionPlugged = false
    hasRequestedCalibration = false
    extensionKind = nil
    accelerometerCalibration = nil
    extensionCenters = [:]
    gyro = nil
    gyroRest = GyroRest()
    motionPlusActive = false
    passthroughBase = nil
    motionSequence = 0
    failure = nil
    refusedReply = nil
  }

  /// A status request, then the report mode that carries the buttons and the accelerometer.
  public func startupWrites() -> [PhysicalOutputWrite] {
    [
      .hidOutput(PhysicalHIDOutputReport(reportID: Self.statusRequestOutputID, bytes: [0x15, 0])),
      reportModeWrite(),
    ]
  }

  /// Returns and clears the writes that parsing queued.
  public func drainPendingWrites() -> [PhysicalOutputWrite] {
    defer { pendingWrites = [] }
    return pendingWrites
  }

  /// The features the report mode carries: the requested ones and, once an extension is read and
  /// known, the extension bytes.
  var chosenFeatures: Set<ProtocolDescription.WiiRemote.BlockKind> {
    guard case .known = extensionKind else { return requestedFeatures }
    return requestedFeatures.union([.extensionData])
  }

  /// The `0x12` write for the smallest mode that carries `chosenFeatures`
  /// (`ReportModeSelect`); the continuous bit is set when the mode carries more than buttons.
  func reportModeWrite() -> PhysicalOutputWrite {
    guard let choice = wii.modeChoices.first(where: { $0.features == chosenFeatures }),
      let mode = wii.reportModes.first(where: { $0.id == choice.mode })
    else {
      preconditionFailure("nintendo-wii.json chooses no mode for \(chosenFeatures)")
    }
    let continuous = mode.blocks.contains { $0.kind != .buttons }
    return .hidOutput(
      PhysicalHIDOutputReport(
        reportID: Self.reportModeOutputID,
        bytes: [Self.reportModeOutputID, continuous ? Self.continuousBit : 0, choice.mode]
      )
    )
  }

  /// Decodes a status report into the power facts, and a data report that has a `Buttons` block
  /// into the buttons and the accelerometer; any other report, or a short one, gives nil.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    guard let id = bytes.first else { return nil }
    expireExchange(at: receivedAt)
    switch id {
    case Self.statusReportID: return parseStatus(bytes, at: receivedAt)
    case Self.memoryReplyReportID, Self.acknowledgementReportID:
      handleReply(bytes, at: receivedAt)
      return nil
    default: break
    }
    guard let mode = wii.reportModes.first(where: { $0.id == id }),
      let buttons = mode.blocks.first(where: { $0.kind == .buttons }),
      bytes.count >= 1 + (mode.blocks.last.map { $0.offset + $0.length } ?? 0)
    else { return nil }
    let core = Array(bytes[(1 + buttons.offset)..<(1 + buttons.offset + buttons.length)])
    var next = state
    for button in wii.coreButtons {
      next.set(button.control, pressed: core[button.field.byte] & button.field.mask != 0)
    }
    var motion: [ControllerMotionSample] = []
    if let block = mode.blocks.first(where: { $0.kind == .accelerometer }), block.length == 3 {
      acceleration = rawAcceleration(
        high: Array(bytes[(1 + block.offset)..<(1 + block.offset + 3)]),
        core: core
      )
    }
    if let block = mode.blocks.first(where: { $0.kind == .extensionData }) {
      let start = 1 + block.offset
      decodeExtension(Array(bytes[start..<start + 6]), into: &next)
    }
    if acceleration != nil, mode.blocks.contains(where: { $0.kind == .accelerometer }) {
      motion = motionSamples(at: receivedAt)
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next, motion: motion)
  }

  /// Takes the battery level, restores the report mode and follows the extension flag.
  ///
  /// The remote drops its report mode after a status report, so the chosen mode goes out again
  /// (`ReportModeRestore`). Only a removed extension yields an event: the controls it drove return
  /// to neutral.
  private func parseStatus(_ bytes: [UInt8], at now: MonotonicTimestamp) -> ControllerEvent? {
    guard bytes.count >= 7 else { return nil }
    isBatteryLow = bytes[3] & Self.batteryLowBit != 0
    let percentage = UInt8(min(100, Int(bytes[6]) * 100 / Self.batteryFull))
    power = ControllerConnectionState.Power(
      charging: .notChargeable,
      battery: BatteryLevel(percentage: percentage...percentage),
      wiredPower: nil
    )
    let plugged = bytes[3] & Self.extensionBit != 0
    let removed = isExtensionPlugged && !plugged
    let added = plugged && !isExtensionPlugged
    isExtensionPlugged = plugged
    if removed { dropExtension(at: now) }
    pendingWrites.append(reportModeWrite())
    if !hasRequestedCalibration {
      hasRequestedCalibration = true
      begin(.accelerometerCalibration, at: now)
    }
    if added { begin(motionPlusActive ? .motionPlusIdentify : .extensionHandshake, at: now) }
    return removed ? ControllerEvent(timestamp: now, state: state) : nil
  }

  /// The 10-bit reading of each axis: the high byte, then the low bits from the button bytes.
  private func rawAcceleration(high: [UInt8], core: [UInt8]) -> RawAcceleration {
    let low = wii.accelerometerLowBits
    func axis(_ high: UInt8, _ field: ProtocolDescription.WiiRemote.BitField) -> Int {
      let bits = Int(core[field.byte] & field.mask) >> field.mask.trailingZeroBitCount
      // Y and Z carry only the upper of the two low bits.
      return Int(high) << 2 | (field.mask.nonzeroBitCount == 1 ? bits << 1 : bits)
    }
    return RawAcceleration(
      x: axis(high[0], low.x),
      y: axis(high[1], low.y),
      z: axis(high[2], low.z)
    )
  }
}
