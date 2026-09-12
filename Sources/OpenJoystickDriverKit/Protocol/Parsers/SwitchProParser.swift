import Foundation

private let switchProFullReportID: UInt8 = 0x30
private let switchProFullReportMinLength = 12
private let switchProStickCenter: UInt16 = 2048
private let switchProStickMax: Float = 2047
private let switchProDeadzone: Float = 0.08

public enum NintendoControllerLayout: Sendable {
  case pro
  case leftJoyCon
  case rightJoyCon
}

/// Parser for Nintendo Switch Pro Controller and Joy-Con full input reports.
///
/// Linux `hid-nintendo.c` uses report `0x30`, a packed 24-bit button field,
/// and two packed 12-bit stick fields. This experimental slice uses default
/// center calibration until physical hardware can verify SPI calibration reads.
public final class SwitchProParser: InputParser, HIDStartupOutputReportProvider,
  HIDStartupRecoveryProvider, PhysicalHIDRumbleOutput, PhysicalHIDPlayerIndicatorOutput,
  @unchecked Sendable
{

  private enum ReportOffset {
    static let reportID = 0
    static let buttons = 3
    static let leftStick = 6
    static let rightStick = 9
  }

  public let layout: NintendoControllerLayout
  private var sensorSamples = NintendoSensorSamples()
  private var motionCalibration = NintendoMotionCalibration.nominal
  private var pendingMotionCalibration: Set<UInt32> = []
  private var factoryMotionBytes: [UInt8]?
  private var userMotionBytes: [UInt8]?
  private var prevButtons: UInt32 = 0
  private var prevDpad: UInt32 = 0
  private var prevLX: UInt16 = switchProStickCenter
  private var prevLY: UInt16 = switchProStickCenter
  private var prevRX: UInt16 = switchProStickCenter
  private var prevRY: UInt16 = switchProStickCenter
  private var outputPacketNumber: UInt8 = 0
  private var physicalRumbleData =
    SwitchProRumbleCodec.encode(intensity: 0) + SwitchProRumbleCodec.encode(intensity: 0)

  public init(layout: NintendoControllerLayout = .pro) { self.layout = layout }

  public var physicalRumbleMotors: [PhysicalRumbleMotor] {
    switch layout {
    case .pro: [.leftMain, .rightMain]
    case .leftJoyCon: [.leftMain]
    case .rightJoyCon: [.rightMain]
    }
  }

  public var physicalInputCapabilities: PhysicalControllerInputCapabilities {
    let buttons: [Button]
    switch layout {
    case .pro: buttons = []
    case .leftJoyCon: buttons = [.leftSL, .leftSR]
    case .rightJoyCon: buttons = [.rightSL, .rightSR]
    }
    return PhysicalControllerInputCapabilities(rawMotion: true, additionalButtons: buttons)
  }

  public var minimumPhysicalOutputIntervalNanoseconds: UInt64 { 50_000_000 }

  public func performHandshake(handle: (any USBTransportSession)?) async throws {
    await Task.yield()
  }

  public func hidStartupReports() -> [PhysicalHIDOutputReport] {
    let prefix = layout == .pro
      ? [usbCommand(0x02), usbCommand(0x03), usbCommand(0x02), usbCommand(0x04)] : []
    return prefix + [
      subcommand(0x03, data: [0x30]), subcommand(0x40, data: [0x01]),
      subcommand(0x48, data: [0x01])
    ] + motionCalibrationRequests()
  }

  public func hidStartupReports(transport: String?) -> [PhysicalHIDOutputReport] {
    switch transport {
    case "USB": return hidStartupReports()
    case "Bluetooth":
      return [
        subcommand(0x03, data: [0x30]), subcommand(0x40, data: [0x01]),
        subcommand(0x48, data: [0x01])
      ] + motionCalibrationRequests()
    default: return []
    }
  }

  public func hidStartupReportIntervalNanoseconds(transport: String?) -> UInt64 {
    transport == "Bluetooth" ? 60_000_000 : 20_000_000
  }

  public func physicalRumbleReport(left: UInt8, right: UInt8, lt _: UInt8, rt _: UInt8)
    -> PhysicalHIDOutputReport
  {
    physicalRumbleData =
      SwitchProRumbleCodec.encode(intensity: layout == .rightJoyCon ? 0 : left)
      + SwitchProRumbleCodec.encode(intensity: layout == .leftJoyCon ? 0 : right)
    var bytes = [UInt8](repeating: 0, count: 10)
    bytes[0] = 0x10
    bytes[1] = nextPacketNumber()
    bytes.replaceSubrange(2..<10, with: physicalRumbleData)
    return PhysicalHIDOutputReport(reportID: 0x10, bytes: bytes)
  }

  public func physicalPlayerIndicatorReport(_ indicator: PhysicalPlayerIndicator)
    -> PhysicalHIDOutputReport
  {
    let patterns: [PhysicalPlayerIndicator: UInt8] = [
      .off: 0x00, .player1: 0x01, .player2: 0x03, .player3: 0x07, .player4: 0x0F
    ]
    return subcommand(0x30, data: [patterns[indicator] ?? 0])
  }

  public func parse(data: Data) throws -> [ControllerEvent] {
    try parse(data: data, receivedAtNanoseconds: DispatchTime.now().uptimeNanoseconds)
  }

  public func parse(data: Data, receivedAtNanoseconds: UInt64) throws -> [ControllerEvent] {
    let bytes = Array(data)
    if bytes.first == 0x21 {
      consumeMotionCalibrationReply(bytes)
      return []
    }
    guard bytes.count >= switchProFullReportMinLength,
      bytes[ReportOffset.reportID] == switchProFullReportID
    else { return [] }

    let buttonMask: UInt32
    switch layout {
    case .pro: buttonMask = 0x00FF_FFFF
    case .leftJoyCon: buttonMask = 0x00FF_2900
    case .rightJoyCon: buttonMask = 0x0000_16FF
    }
    let buttons = readUInt24LE(bytes, offset: ReportOffset.buttons) & buttonMask
    let left = readStick(bytes, offset: ReportOffset.leftStick)
    let right = readStick(bytes, offset: ReportOffset.rightStick)

    var events: [ControllerEvent] = []
    events.append(contentsOf: parseButtons(buttons))
    events.append(contentsOf: parseDpad(buttons))
    events.append(contentsOf: parseSticks(left: left, right: right))

    events.append(contentsOf: sensorSamples.decode(
      bytes, receivedAt: receivedAtNanoseconds, layout: layout, calibration: motionCalibration
    ))
    prevButtons = buttons
    prevDpad = buttons & 0x000F_0000
    prevLX = left.x
    prevLY = left.y
    prevRX = right.x
    prevRY = right.y

    return events
  }

  private func usbCommand(_ command: UInt8) -> PhysicalHIDOutputReport {
    PhysicalHIDOutputReport(reportID: 0x80, bytes: [0x80, command])
  }

  private func motionCalibrationRequests() -> [PhysicalHIDOutputReport] {
    pendingMotionCalibration = [0x6020, 0x8026]
    factoryMotionBytes = nil
    userMotionBytes = nil
    return pendingHIDStartupReports()
  }

  public func pendingHIDStartupReports() -> [PhysicalHIDOutputReport] {
    pendingMotionCalibration.sorted().map { address in
      let length: UInt8 = address == 0x6020 ? 24 : 20
      return subcommand(0x10, data: [
        UInt8(truncatingIfNeeded: address), UInt8(truncatingIfNeeded: address >> 8), 0, 0, length
      ])
    }
  }

  public func expireHIDStartupRequests() {
    pendingMotionCalibration.removeAll()
    factoryMotionBytes = nil
    userMotionBytes = nil
  }

  private func consumeMotionCalibrationReply(_ bytes: [UInt8]) {
    guard bytes.count >= 20, bytes[13] & 0x80 != 0, bytes[14] == 0x10
    else { return }
    let address = UInt32(bytes[15]) | (UInt32(bytes[16]) << 8)
      | (UInt32(bytes[17]) << 16) | (UInt32(bytes[18]) << 24)
    guard pendingMotionCalibration.contains(address) else { return }
    let length = address == 0x6020 ? 24 : 20
    guard Int(bytes[19]) == length, bytes.count >= 20 + length else { return }
    let data = Array(bytes[20..<(20 + length)])
    if address == 0x6020 {
      guard NintendoMotionCalibration.factory(data) != nil else { return }
      factoryMotionBytes = data
    } else {
      userMotionBytes = data[0] == 0xB2 && data[1] == 0xA1 ? data : nil
    }
    pendingMotionCalibration.remove(address)
    guard let factoryMotionBytes,
      let factory = NintendoMotionCalibration.factory(factoryMotionBytes)
    else { return }
    let calibrated = userMotionBytes.flatMap {
      NintendoMotionCalibration.factory(factoryMotionBytes, userOffsets: $0)
    } ?? factory
    motionCalibration = calibrated.installed(after: motionCalibration)
  }

  private func subcommand(_ id: UInt8, data: [UInt8]) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: 11 + data.count)
    bytes[0] = 0x01
    bytes[1] = nextPacketNumber()
    bytes.replaceSubrange(2..<10, with: physicalRumbleData)
    bytes[10] = id
    for (index, value) in data.enumerated() { bytes[11 + index] = value }
    return PhysicalHIDOutputReport(reportID: 0x01, bytes: bytes)
  }

  private func nextPacketNumber() -> UInt8 {
    defer { outputPacketNumber = (outputPacketNumber + 1) & 0x0F }
    return outputPacketNumber
  }

  private func parseButtons(_ buttons: UInt32) -> [ControllerEvent] {
    var mapping: [(UInt32, Button)] = []
    switch layout {
    case .pro: break
    case .leftJoyCon: mapping = [(0x0020_0000, .leftSL), (0x0010_0000, .leftSR)]
    case .rightJoyCon: mapping = [(0x0000_0020, .rightSL), (0x0000_0010, .rightSR)]
    }
    return diffButtons(
      prev: prevButtons,
      curr: buttons,
      mapping: mapping + [
        (0x0000_0008, .b), (0x0000_0004, .a), (0x0000_0002, .y), (0x0000_0001, .x),
        (0x0040_0000, .leftBumper), (0x0000_0040, .rightBumper), (0x0080_0000, .l2Digital),
        (0x0000_0080, .r2Digital), (0x0000_0100, .back), (0x0000_0200, .start),
        (0x0000_0800, .leftStick), (0x0000_0400, .rightStick), (0x0000_1000, .guide),
        (0x0000_2000, .share)
      ]
    )
  }

  private func parseDpad(_ buttons: UInt32) -> [ControllerEvent] {
    let dpad = buttons & 0x000F_0000
    guard dpad != prevDpad else { return [] }
    let up = (buttons & 0x0002_0000) != 0
    let down = (buttons & 0x0001_0000) != 0
    let right = (buttons & 0x0004_0000) != 0
    let left = (buttons & 0x0008_0000) != 0
    return [.dpadChanged(mapDpad(up: up, right: right, down: down, left: left))]
  }

  private func parseSticks(left: (x: UInt16, y: UInt16), right: (x: UInt16, y: UInt16))
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    if layout != .rightJoyCon, left.x != prevLX || left.y != prevLY {
      events.append(.leftStickChanged(x: normalizeStick(left.x), y: -normalizeStick(left.y)))
    }
    if layout != .leftJoyCon, right.x != prevRX || right.y != prevRY {
      events.append(.rightStickChanged(x: normalizeStick(right.x), y: -normalizeStick(right.y)))
    }
    return events
  }

  private func diffButtons(prev: UInt32, curr: UInt32, mapping: [(UInt32, Button)])
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    for (mask, button) in mapping {
      let wasPressed = (prev & mask) != 0
      let isPressed = (curr & mask) != 0
      if wasPressed != isPressed {
        events.append(isPressed ? .buttonPressed(button) : .buttonReleased(button))
      }
    }
    return events
  }

  private func readUInt24LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16)
  }

  private func readStick(_ bytes: [UInt8], offset: Int) -> (x: UInt16, y: UInt16) {
    let x = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1] & 0x0F) << 8)
    let y = (UInt16(bytes[offset + 1]) >> 4) | (UInt16(bytes[offset + 2]) << 4)
    return (x, y)
  }

  private func normalizeStick(_ value: UInt16) -> Float {
    let centered = Float(Int(value) - Int(switchProStickCenter)) / switchProStickMax
    if abs(centered) < switchProDeadzone { return 0 }
    return max(-1, min(1, centered))
  }

  private func mapDpad(up: Bool, right: Bool, down: Bool, left: Bool) -> DpadDirection {
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
