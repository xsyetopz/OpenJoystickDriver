import Foundation
import SwiftUSB

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
private let ds3BluetoothOperationalReportID: UInt8 = 0xF4
private let ds3Deadzone: Float = 0.08
private let ds3OutputReportID: UInt8 = 0x01
private let ds3OutputReportLength = 36

/// Parser for Sony DualShock 3 / SIXAXIS USB and Bluetooth input reports.
///
/// Linux `hid-sony.c` maps the DS3's button usages, sticks, and L2/R2 analog
/// usages. The native SIXAXIS descriptor uses report ID `0x01`, one reserved
/// byte, digital button bits including D-pad usages, four 8-bit stick axes,
/// and pressure axes later in the
/// 49-byte report. Physical rumble and player LEDs use the fixed 36-byte
/// Sixaxis output report from Linux `hid-sony.c`; sensors remain intentionally omitted.
public final class DS3Parser: InputParser, HIDStartupFeatureReadRequestProvider,
  HIDStartupFeatureReportProvider, PhysicalHIDRumbleOutput,
  PhysicalHIDPlayerIndicatorOutput, @unchecked Sendable
{

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

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevButtons2: UInt8 = 0
  private var prevDpad: UInt8 = 0
  private var prevLX = UInt8(ds3AxisCenter)
  private var prevLY = UInt8(ds3AxisCenter)
  private var prevRX = UInt8(ds3AxisCenter)
  private var prevRY = UInt8(ds3AxisCenter)
  private var prevL2: UInt8 = 0
  private var prevR2: UInt8 = 0
  private var physicalRumbleLeft: UInt8 = 0
  private var physicalRumbleRightOn = false
  private var physicalPlayerIndicator: PhysicalPlayerIndicator = .player1

  public init() {}

  public var physicalBinaryRumbleMotors: [PhysicalRumbleMotor] { [.rightMain] }

  public func performHandshake(handle: USBDeviceHandle?) async throws {
    await Task.yield()
  }

  public func hidStartupFeatureReadRequests() -> [PhysicalHIDFeatureReadRequest] {
    [
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

  public func hidStartupFeatureReadRequests(transport: String?) -> [PhysicalHIDFeatureReadRequest] {
    guard transport == "USB" else { return [] }
    return hidStartupFeatureReadRequests()
  }

  public func hidStartupFeatureReports() -> [PhysicalHIDOutputReport] {
    []
  }

  public func hidStartupFeatureReports(transport: String?) -> [PhysicalHIDOutputReport] {
    guard transport == "Bluetooth" else { return [] }
    return [
      PhysicalHIDOutputReport(
        reportID: ds3BluetoothOperationalReportID,
        bytes: [ds3BluetoothOperationalReportID, 0x42, 0x03, 0x00, 0x00]
      ),
    ]
  }

  public func physicalRumbleReport(left: UInt8, right: UInt8, lt _: UInt8, rt _: UInt8)
    -> PhysicalHIDOutputReport
  {
    physicalRumbleLeft = left
    physicalRumbleRightOn = right > 0
    return physicalOutputReport()
  }

  public func physicalPlayerIndicatorReport(_ indicator: PhysicalPlayerIndicator)
    -> PhysicalHIDOutputReport
  {
    physicalPlayerIndicator = indicator
    return physicalOutputReport()
  }

  private func physicalOutputReport() -> PhysicalHIDOutputReport {
    var bytes: [UInt8] = [
      0x01,
      0x01, 0xFF, 0x00, 0xFF, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0xFF, 0x27, 0x10, 0x00, 0x32,
      0x00, 0x00, 0x00, 0x00, 0x00,
    ]
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

  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = Array(data)
    guard bytes.count >= ds3InputReportLength,
      bytes[ReportOffset.reportID] == ds3InputReportID,
      bytes[1] != 0xFF
    else { return [] }

    let b0 = bytes[ReportOffset.buttons0]
    let b1 = bytes[ReportOffset.buttons1]
    let b2 = bytes[ReportOffset.buttons2]
    let lx = bytes[ReportOffset.leftX]
    let ly = bytes[ReportOffset.leftY]
    let rx = bytes[ReportOffset.rightX]
    let ry = bytes[ReportOffset.rightY]
    let l2 = bytes[ReportOffset.l2Analog]
    let r2 = bytes[ReportOffset.r2Analog]

    var events: [ControllerEvent] = []
    events.append(contentsOf: parseButtons(buttons0: b0, buttons1: b1, buttons2: b2))
    events.append(contentsOf: parseDpad(buttons0: b0))
    events.append(contentsOf: parseSticks(leftX: lx, leftY: ly, rightX: rx, rightY: ry))
    events.append(contentsOf: parseTriggers(left: l2, right: r2))

    prevButtons0 = b0
    prevButtons1 = b1
    prevButtons2 = b2
    prevDpad = b0 & 0xF0
    prevLX = lx
    prevLY = ly
    prevRX = rx
    prevRY = ry
    prevL2 = l2
    prevR2 = r2

    return events
  }

  private func parseButtons(buttons0 b0: UInt8, buttons1 b1: UInt8, buttons2 b2: UInt8)
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    events.append(contentsOf: diffButtons(prev: prevButtons0, curr: b0, mapping: [
      (0x01, .back),
      (0x02, .leftStick),
      (0x04, .rightStick),
      (0x08, .start),
    ]))
    events.append(contentsOf: diffButtons(prev: prevButtons1, curr: b1, mapping: [
      (0x01, .l2Digital),
      (0x02, .r2Digital),
      (0x04, .l1),
      (0x08, .r1),
      (0x10, .triangle),
      (0x20, .circle),
      (0x40, .cross),
      (0x80, .square),
    ]))
    events.append(contentsOf: diffButtons(prev: prevButtons2, curr: b2, mapping: [
      (0x01, .ps),
    ]))
    return events
  }

  private func parseDpad(buttons0: UInt8) -> [ControllerEvent] {
    let dpad = buttons0 & 0xF0
    guard dpad != prevDpad else { return [] }
    let up = (buttons0 & 0x10) != 0
    let right = (buttons0 & 0x20) != 0
    let down = (buttons0 & 0x40) != 0
    let left = (buttons0 & 0x80) != 0
    return [.dpadChanged(mapDpad(up: up, right: right, down: down, left: left))]
  }

  private func parseSticks(leftX: UInt8, leftY: UInt8, rightX: UInt8, rightY: UInt8)
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    if leftX != prevLX || leftY != prevLY {
      events.append(.leftStickChanged(x: normalizeAxis(leftX), y: -normalizeAxis(leftY)))
    }
    if rightX != prevRX || rightY != prevRY {
      events.append(.rightStickChanged(x: normalizeAxis(rightX), y: -normalizeAxis(rightY)))
    }
    return events
  }

  private func parseTriggers(left: UInt8, right: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if left != prevL2 { events.append(.leftTriggerChanged(Float(left) / ds3TriggerMax)) }
    if right != prevR2 { events.append(.rightTriggerChanged(Float(right) / ds3TriggerMax)) }
    return events
  }

  private func diffButtons(prev: UInt8, curr: UInt8, mapping: [(UInt8, Button)])
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

  private func normalizeAxis(_ value: UInt8) -> Float {
    let centered = Float(value) - ds3AxisCenter
    let divisor = centered >= 0 ? ds3AxisPositiveMax : ds3AxisNegativeMax
    let normalized = centered / divisor
    if abs(normalized) < ds3Deadzone { return 0 }
    return max(-1, min(1, normalized))
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
