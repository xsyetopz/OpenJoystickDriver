import Foundation

/// Driver for the Wii Remote over Bluetooth HID: core buttons, the accelerometer, status and
/// battery.
///
/// The report layouts, the button and accelerometer bits and the report-mode choice come from the
/// `wiiRemote` field of `nintendo-wii.json`. Facts are from WiiBrew's Wiimote page. Extensions,
/// IR, the speaker, LEDs and rumble are not decoded or written yet.
public final class WiiDriver: PhysicalProtocolDriver {
  /// The input report that answers a status request and carries the battery.
  private static let statusReportID: UInt8 = 0x20
  /// The output report that sets the data reporting mode.
  private static let reportModeOutputID: UInt8 = 0x12
  /// The output report that requests a status report.
  private static let statusRequestOutputID: UInt8 = 0x15
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
  private let wii: ProtocolDescription.WiiRemote
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The latest power facts from a status report.
  public private(set) var power: ControllerConnectionState.Power?
  /// Whether the latest status report set the low-battery flag.
  public private(set) var isBatteryLow = false
  /// The accelerometer reading of the latest report that carried one.
  private(set) var acceleration: RawAcceleration?

  /// Creates the driver for the family's description.
  public init() {
    guard let wii = PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote else {
      preconditionFailure("nintendo-wii.json describes no wiiRemote field")
    }
    self.wii = wii
  }

  /// The core buttons of the description.
  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: Set(wii.coreButtons.map(\.control)))
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

  /// Clears the state of the session: neutral input and no reading.
  public func resetProtocolState() {
    state = .neutral
    acceleration = nil
  }

  /// A status request, then the report mode that carries the buttons and the accelerometer.
  public func startupWrites() -> [PhysicalOutputWrite] {
    guard let choice = wii.modeChoices.first(where: { $0.features == [.accelerometer] }) else {
      preconditionFailure("nintendo-wii.json chooses no mode for the accelerometer")
    }
    return [
      .hidOutput(PhysicalHIDOutputReport(reportID: Self.statusRequestOutputID, bytes: [0x15, 0])),
      .hidOutput(
        PhysicalHIDOutputReport(
          reportID: Self.reportModeOutputID,
          bytes: [Self.reportModeOutputID, Self.continuousBit, choice.mode]
        )
      ),
    ]
  }

  /// Decodes a status report into the power facts, and a data report that has a `Buttons` block
  /// into the buttons and the accelerometer; any other report, or a short one, gives nil.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    guard let id = bytes.first else { return nil }
    if id == Self.statusReportID { return parseStatus(bytes) }
    guard let mode = wii.reportModes.first(where: { $0.id == id }),
      let buttons = mode.blocks.first(where: { $0.kind == .buttons }),
      bytes.count >= 1 + (mode.blocks.last.map { $0.offset + $0.length } ?? 0)
    else { return nil }
    let core = Array(bytes[(1 + buttons.offset)..<(1 + buttons.offset + buttons.length)])
    var next = state
    for button in wii.coreButtons {
      next.set(button.control, pressed: core[button.field.byte] & button.field.mask != 0)
    }
    if let block = mode.blocks.first(where: { $0.kind == .accelerometer }), block.length == 3 {
      acceleration = rawAcceleration(
        high: Array(bytes[(1 + block.offset)..<(1 + block.offset + 3)]),
        core: core
      )
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// Takes the battery level and the low-battery flag of a status report; the report carries no
  /// input event.
  private func parseStatus(_ bytes: [UInt8]) -> ControllerEvent? {
    guard bytes.count >= 7 else { return nil }
    isBatteryLow = bytes[3] & Self.batteryLowBit != 0
    let percentage = UInt8(min(100, Int(bytes[6]) * 100 / Self.batteryFull))
    power = ControllerConnectionState.Power(
      charging: .notChargeable,
      battery: BatteryLevel(percentage: percentage...percentage),
      wiredPower: nil
    )
    return nil
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
