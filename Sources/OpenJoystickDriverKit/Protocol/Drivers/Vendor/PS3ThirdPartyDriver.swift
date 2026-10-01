import Foundation

private let ps3ThirdPartyAxisCenter: Float = 128
private let ps3ThirdPartyAxisPositiveMax: Float = 127
private let ps3ThirdPartyAxisNegativeMax: Float = 128
private let ps3ThirdPartyTriggerMax: Float = 255
/// A pressure byte counts as pressed once bit 7 is set, so light pressure and noise are ignored.
private let ps3ThirdPartyPressedThreshold: UInt8 = 0x80
/// Byte 2 of the probe reply that marks SDL's third-party PS3 report format.
private let ps3ThirdPartyProbeMarker: UInt8 = 0x26

/// Driver for non-Sony PS3 controllers: pads, fight sticks, instruments and adapters sold for
/// the PS3 that do not speak Sony's DualShock 3 protocol.
///
/// It follows SDL's `HIDAPI_DriverPS3ThirdParty`. A startup feature read of report `0x03` (or,
/// for devices without report IDs, report `0x00`) whose reply carries `0x26` at SDL's byte 2
/// identifies the fixed third-party report format. The descriptor's logical ranges do not match
/// that format, so the driver then decodes raw reports by byte offset. A device that fails the
/// probe keeps the generic HID descriptor mapping, which SDL also falls back to. Pads SDL
/// accepts without a probe (Logitech ChillStream, Ant Esports GP100) have records in the
/// `hid.report-layout` family instead, which ``ReportLayoutDriver`` decodes.
///
/// Raw reports of 19 or more bytes carry face and shoulder bits and digital triggers in byte 0,
/// system buttons in byte 1, a hat in the low nibble of byte 2, sticks in bytes 3–6, per-button
/// pressure in bytes 7–16 and analog triggers in bytes 17–18. The 18-byte format (Logitech
/// ChillStream) drops the digital triggers and Guide, moves the hat to the high nibble of byte 1
/// and shifts the rest down by one byte. A button counts as pressed from its digital bit or from
/// bit 7 of its pressure byte. SDL decodes the hat only when its byte changes from the previous
/// report, starting from zero, so a hat that stays `0` never reads as held north; the driver
/// matches that by using the D-pad pressure bytes until the hat nibble is nonzero.
///
/// The record quirk `dpad-pressure` (Saitek Cyborg V.3) ignores the hat nibble and reads any
/// nonzero D-pad pressure as held, as SDL does for that pad.
///
/// Only a pad whose controller record names a rumble template drives rumble. SDL's third-party
/// driver sends no output, because some of these pads then rumble without stopping.
public final class PS3ThirdPartyDriver: PhysicalProtocolDriver {

  private enum Layout {
    /// Reports of 19 bytes or more.
    case standard
    /// 18-byte reports (Logitech ChillStream).
    case compact

    var stickOffset: Int { self == .standard ? 3 : 2 }
    var pressureOffset: Int { self == .standard ? 7 : 6 }
    var triggerOffset: Int { self == .standard ? 17 : 16 }
  }

  /// Pressure byte order from the layout's pressure offset.
  private enum Pressure {
    static let dpadRight = 0
    static let dpadLeft = 1
    static let dpadUp = 2
    static let dpadDown = 3
    static let north = 4
    static let east = 5
    static let south = 6
    static let west = 7
    static let leftShoulder = 8
    static let rightShoulder = 9
  }

  private enum ProbeReport {
    static let withReportID: UInt8 = 0x03
    static let withoutReportID: UInt8 = 0x00
    static let length = 64
    static let replyLength = 8
  }

  private let descriptorFallback: HIDDescriptorDriver
  private let hatFromPressureOnly: Bool
  private let rumbleTemplate: RumbleOutputTemplate?
  /// Set once the hat nibble has been nonzero in this session.
  private var hatIsLive = false
  /// Set once the device is known to send the third-party report format.
  private(set) var decodesRawReports: Bool
  private var state = ControllerState.neutral

  /// Creates a driver for the controller at `identifier`. `rumbleTemplate` and
  /// `hatFromPressureOnly` (quirk `dpad-pressure`) come from its record.
  public init(
    identifier: DeviceIdentifier,
    rumbleTemplate: RumbleOutputTemplate? = nil,
    hatFromPressureOnly: Bool = false
  ) {
    descriptorFallback = HIDDescriptorDriver(identifier: identifier)
    self.hatFromPressureOnly = hatFromPressureOnly
    self.rumbleTemplate = rumbleTemplate
    decodesRawReports = false
  }

  /// A new transport session starts from neutral input. The probe result describes the device,
  /// so it survives.
  public func resetProtocolState() {
    state = .neutral
    hatIsLive = false
    descriptorFallback.resetProtocolState()
  }

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(parsesHIDElementValues: true, validatesFeatureReplies: true)
  }
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: ControlID.xboxLayout.union([.guide]))
  }

  /// Rumble through the record's template; the motors run until the next report.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    return try rumbleTemplate.encode(command)
  }

  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    guard !decodesRawReports else { return [] }
    return [
      PhysicalHIDFeatureReadRequest(reportID: ProbeReport.withReportID, length: ProbeReport.length),
      PhysicalHIDFeatureReadRequest(
        reportID: ProbeReport.withoutReportID,
        length: ProbeReport.length
      ),
    ]
  }

  /// Accepts SDL's probe reply. IOKit returns the report-ID byte for report `0x03` but not for
  /// report `0x00`, where hidapi prepends one, so SDL's byte 2 is byte 1 of that reply.
  /// A rejected reply leaves the descriptor mapping in place.
  public func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    // The first accepted probe decides; a later request has nothing left to prove.
    guard !decodesRawReports else { return true }
    let bytes = [UInt8](data)
    guard bytes.count == ProbeReport.replyLength else { return false }
    let markerOffset: Int
    switch request.reportID {
    case ProbeReport.withReportID: markerOffset = 2
    case ProbeReport.withoutReportID: markerOffset = 1
    default: return false
    }
    guard bytes[markerOffset] == ps3ThirdPartyProbeMarker else { return false }
    decodesRawReports = true
    state = .neutral
    return true
  }

  public func parse(
    elementValue value: HIDElementValue,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard !decodesRawReports else { return nil }
    return descriptorFallback.parse(elementValue: value, receivedAt: receivedAt)
  }

  /// Decodes one third-party PS3 input report into the full controller state.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    guard decodesRawReports else { return nil }
    let bytes = [UInt8](data)
    let layout: Layout
    switch bytes.count {
    case 19...: layout = .standard
    case 18: layout = .compact
    default: return nil
    }
    var next = state
    let digital = bytes[0]
    decodeButtons(bytes, digital: digital, layout: layout, into: &next)
    next.hat = hat(bytes, layout: layout)
    let triggers = layout.triggerOffset
    let digitalTriggers = layout == .standard ? digital : 0
    next.leftTrigger = Self.trigger(bytes[triggers], digital: digitalTriggers & 0x40 != 0)
    next.rightTrigger = Self.trigger(bytes[triggers + 1], digital: digitalTriggers & 0x80 != 0)
    let sticks = layout.stickOffset
    next.leftStick = StickPosition(x: Self.axis(bytes[sticks]), yDown: Self.axis(bytes[sticks + 1]))
    next.rightStick = StickPosition(
      x: Self.axis(bytes[sticks + 2]),
      yDown: Self.axis(bytes[sticks + 3])
    )
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  private func decodeButtons(
    _ bytes: [UInt8],
    digital: UInt8,
    layout: Layout,
    into next: inout ControllerState
  ) {
    let pressure = layout.pressureOffset
    for (mask, offset, control) in [
      (UInt8(0x01), Pressure.west, ControlID.faceWest), (0x02, Pressure.south, .faceSouth),
      (0x04, Pressure.east, .faceEast), (0x08, Pressure.north, .faceNorth),
      (0x10, Pressure.leftShoulder, .leftShoulder), (0x20, Pressure.rightShoulder, .rightShoulder),
    ] {
      let pressed =
        digital & mask != 0 || bytes[pressure + offset] & ps3ThirdPartyPressedThreshold != 0
      next.set(control, pressed: pressed)
    }
    var system: [(UInt8, ControlID)] = [
      (0x01, .view), (0x02, .menu), (0x04, .leftStickClick), (0x08, .rightStickClick),
    ]
    if layout == .standard { system.append((0x10, .guide)) }
    for (mask, control) in system { next.set(control, pressed: bytes[1] & mask != 0) }
  }

  /// The hat nibble, or the D-pad pressure bytes when the nibble is centered or untrusted.
  private func hat(_ bytes: [UInt8], layout: Layout) -> HatDirection {
    let nibble = layout == .standard ? bytes[2] & 0x0F : bytes[1] >> 4
    if nibble != 0 { hatIsLive = true }
    let directions = HatDirection.clockwiseFromNorth
    if hatIsLive, !hatFromPressureOnly, Int(nibble) < directions.count {
      return directions[Int(nibble)]
    }
    let pressure = layout.pressureOffset
    // The Cyborg V.3 reports any nonzero D-pad pressure as held, as SDL reads it.
    let threshold: UInt8 = hatFromPressureOnly ? 0x01 : ps3ThirdPartyPressedThreshold
    func held(_ offset: Int) -> Bool { bytes[pressure + offset] >= threshold }
    return HatDirection(
      up: held(Pressure.dpadUp),
      right: held(Pressure.dpadRight),
      down: held(Pressure.dpadDown),
      left: held(Pressure.dpadLeft)
    )
  }

  private static func trigger(_ raw: UInt8, digital: Bool) -> UnipolarValue {
    UnipolarValue(normalized: digital ? 1 : Float(raw) / ps3ThirdPartyTriggerMax)
  }

  /// Converts one unsigned axis byte, centered on 128 with up and left low, to -1...1.
  static func axis(_ raw: UInt8) -> Float {
    let centered = Float(raw) - ps3ThirdPartyAxisCenter
    let divisor = centered >= 0 ? ps3ThirdPartyAxisPositiveMax : ps3ThirdPartyAxisNegativeMax
    return max(-1, min(1, centered / divisor))
  }
}
