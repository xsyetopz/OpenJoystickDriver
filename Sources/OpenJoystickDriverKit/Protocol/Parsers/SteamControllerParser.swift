import Foundation
import SwiftUSB

private enum SteamControllerReportLayout {
  static let prefix0: UInt8 = 0x01
  static let prefix1: UInt8 = 0x00
  static let stateMessageID: UInt8 = 0x01
  static let wirelessMessageID: UInt8 = 0x03
  static let statusMessageID: UInt8 = 0x04
  static let reportLength = 64
  static let triggerMax: Float = 255
  static let stickMax: Float = 32_767
  static let deadzone: Float = 0.08
  static let wirelessDisconnected: UInt8 = 0x01
  static let wirelessConnected: UInt8 = 0x02
}

private enum SteamControllerCommand {
  static let setDefaultDigitalMappings: UInt8 = 0x85
  static let loadDefaultSettings: UInt8 = 0x8E
  static let clearDigitalMappings: UInt8 = 0x81
  static let setSettingsValues: UInt8 = 0x87
  static let getWirelessState: UInt8 = 0xB4
  static let trackpadNone: UInt8 = 0x07
  static let leftTrackpadModeSetting: UInt8 = 0x07
  static let rightTrackpadModeSetting: UInt8 = 0x08
}

/// Parser for Valve Steam Controller input reports.
///
/// Linux `hid-steam.c` receives 64-byte raw events prefixed with `0x01, 0x00`.
/// Message type `0x01` carries a 60-byte controller state payload with button
/// bytes at offsets 8-10, analog triggers at 11-12, left stick/left pad axes at
/// 16-19, and right pad axes at 20-23. Source-backed lizard-mode feature
/// reports are sent when OJD starts and stops consuming Steam Controller input.
public final class SteamControllerParser: InputParser, ControllerInputConnectionLifecycle,
  HIDInputConnectionStatusRequester, HIDStartupFeatureReportProvider,
  HIDShutdownFeatureReportProvider, @unchecked Sendable
{

  private enum ReportOffset {
    static let messageType = 2
    static let wirelessStatus = 4
    static let buttons0 = 8
    static let buttons1 = 9
    static let buttons2 = 10
    static let leftTrigger = 11
    static let rightTrigger = 12
    static let leftX = 16
    static let leftY = 18
    static let rightPadX = 20
    static let rightPadY = 22
  }

  private var prevButtons0: UInt8 = 0
  private var prevButtons1: UInt8 = 0
  private var prevButtons2: UInt8 = 0
  private var prevDpad: UInt8 = 0
  private var prevLT: UInt8 = 0
  private var prevRT: UInt8 = 0
  private var prevLX: Int16 = 0
  private var prevLY: Int16 = 0
  private var prevRX: Int16 = 0
  private var prevRY: Int16 = 0
  private let isWirelessReceiver: Bool
  private var isLogicalControllerConnected: Bool
  private var pendingConnectionStateChange: ControllerInputConnectionState?

  /// Creates a new Steam Controller parser.
  public init(isWirelessReceiver: Bool = false) {
    self.isWirelessReceiver = isWirelessReceiver
    isLogicalControllerConnected = !isWirelessReceiver
  }

  public var requiresInputConnectionBeforeOutput: Bool { isWirelessReceiver }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingConnectionStateChange
    pendingConnectionStateChange = nil
    return state
  }

  public func hidStartupFeatureReports() -> [PhysicalHIDOutputReport] {
    [
      steamFeatureReport([SteamControllerCommand.clearDigitalMappings]),
      steamFeatureReport([
        SteamControllerCommand.setSettingsValues, 6, SteamControllerCommand.leftTrackpadModeSetting,
        SteamControllerCommand.trackpadNone, 0, SteamControllerCommand.rightTrackpadModeSetting,
        SteamControllerCommand.trackpadNone, 0,
      ]),
    ]
  }

  public func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport] {
    [
      steamFeatureReport([SteamControllerCommand.setDefaultDigitalMappings]),
      steamFeatureReport([SteamControllerCommand.loadDefaultSettings]),
    ]
  }

  public func inputConnectionStatusRequestReport() -> PhysicalHIDOutputReport? {
    guard isWirelessReceiver else { return nil }
    return steamFeatureReport([SteamControllerCommand.getWirelessState])
  }

  /// No-op for the current experimental input slice.
  public func performHandshake(handle: USBDeviceHandle?) async throws { await Task.yield() }

  /// Parses one Steam Controller state report and returns controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = Array(data)
    guard bytes.count == SteamControllerReportLayout.reportLength,
      bytes[0] == SteamControllerReportLayout.prefix0,
      bytes[1] == SteamControllerReportLayout.prefix1
    else { return [] }

    switch bytes[ReportOffset.messageType] {
    case SteamControllerReportLayout.wirelessMessageID:
      parseWirelessStatus(bytes)
      return []
    case SteamControllerReportLayout.statusMessageID:
      parseWirelessStatusFallback()
      return []
    case SteamControllerReportLayout.stateMessageID:
      guard isLogicalControllerConnected else { return [] }
      return parseControllerState(bytes)
    default: return []
    }
  }

  private func parseWirelessStatus(_ bytes: [UInt8]) {
    guard isWirelessReceiver else { return }
    let nextConnected: Bool
    switch bytes[ReportOffset.wirelessStatus] {
    case SteamControllerReportLayout.wirelessDisconnected: nextConnected = false
    case SteamControllerReportLayout.wirelessConnected: nextConnected = true
    default: return
    }
    guard nextConnected != isLogicalControllerConnected else { return }
    isLogicalControllerConnected = nextConnected
    pendingConnectionStateChange = nextConnected ? .connected : .disconnected
    resetPreviousReportState()
  }

  private func parseWirelessStatusFallback() {
    guard isWirelessReceiver, !isLogicalControllerConnected else { return }
    isLogicalControllerConnected = true
    pendingConnectionStateChange = .connected
    resetPreviousReportState()
  }

  private func parseControllerState(_ bytes: [UInt8]) -> [ControllerEvent] {
    let b0 = bytes[ReportOffset.buttons0]
    let b1 = bytes[ReportOffset.buttons1]
    let b2 = bytes[ReportOffset.buttons2]
    let lt = bytes[ReportOffset.leftTrigger]
    let rt = bytes[ReportOffset.rightTrigger]
    let lpadTouched = (b2 & 0x08) != 0
    let lpadAndJoy = (b2 & 0x80) != 0
    let reportsLeftStick = !lpadTouched || lpadAndJoy
    let lx = reportsLeftStick ? readInt16LE(bytes, offset: ReportOffset.leftX) : 0
    let ly = reportsLeftStick ? clampedNegatedInt16LE(bytes, offset: ReportOffset.leftY) : 0
    let rx = readInt16LE(bytes, offset: ReportOffset.rightPadX)
    let ry = clampedNegatedInt16LE(bytes, offset: ReportOffset.rightPadY)

    var events: [ControllerEvent] = []
    events.append(contentsOf: parseButtons(buttons0: b0, buttons1: b1, buttons2: b2))
    events.append(contentsOf: parseDpad(buttons1: b1))
    events.append(contentsOf: parseTriggers(left: lt, right: rt))
    events.append(contentsOf: parseSticks(leftX: lx, leftY: ly, rightX: rx, rightY: ry))

    prevButtons0 = b0
    prevButtons1 = b1
    prevButtons2 = b2
    prevDpad = b1 & 0x0F
    prevLT = lt
    prevRT = rt
    prevLX = lx
    prevLY = ly
    prevRX = rx
    prevRY = ry

    return events
  }

  private func steamFeatureReport(_ command: [UInt8]) -> PhysicalHIDOutputReport {
    var report = [UInt8](repeating: 0, count: SteamControllerReportLayout.reportLength)
    for (index, byte) in command.prefix(SteamControllerReportLayout.reportLength).enumerated() {
      report[index] = byte
    }
    return PhysicalHIDOutputReport(reportID: 0, bytes: report)
  }

  private func resetPreviousReportState() {
    prevButtons0 = 0
    prevButtons1 = 0
    prevButtons2 = 0
    prevDpad = 0
    prevLT = 0
    prevRT = 0
    prevLX = 0
    prevLY = 0
    prevRX = 0
    prevRY = 0
  }

  private func parseButtons(buttons0 b0: UInt8, buttons1 b1: UInt8, buttons2 b2: UInt8)
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    events.append(
      contentsOf: diffButtons(
        prev: prevButtons0,
        curr: b0,
        mapping: [
          (0x01, .r2Digital), (0x02, .l2Digital), (0x04, .rightBumper), (0x08, .leftBumper),
          (0x10, .y), (0x20, .b), (0x40, .x), (0x80, .a),
        ]
      )
    )
    events.append(
      contentsOf: diffButtons(
        prev: prevButtons1,
        curr: b1,
        mapping: [(0x10, .back), (0x20, .guide), (0x40, .start), (0x80, .genericButton1)]
      )
    )
    events.append(
      contentsOf: diffButtons(
        prev: prevButtons2,
        curr: b2,
        mapping: [
          (0x01, .genericButton2), (0x02, .genericButton3), (0x04, .rightStick),
          (0x10, .genericButton5), (0x40, .leftStick),
        ]
      )
    )
    let wasLeftPadTouched = (prevButtons2 & 0x88) != 0
    let isLeftPadTouched = (b2 & 0x88) != 0
    if wasLeftPadTouched != isLeftPadTouched {
      events.append(
        isLeftPadTouched ? .buttonPressed(.genericButton4) : .buttonReleased(.genericButton4)
      )
    }
    return events
  }

  private func parseDpad(buttons1 b1: UInt8) -> [ControllerEvent] {
    let dpad = b1 & 0x0F
    guard dpad != prevDpad else { return [] }
    return [.dpadChanged(mapDpad(dpad))]
  }

  private func parseTriggers(left: UInt8, right: UInt8) -> [ControllerEvent] {
    var events: [ControllerEvent] = []
    if left != prevLT {
      events.append(.leftTriggerChanged(Float(left) / SteamControllerReportLayout.triggerMax))
    }
    if right != prevRT {
      events.append(.rightTriggerChanged(Float(right) / SteamControllerReportLayout.triggerMax))
    }
    return events
  }

  private func parseSticks(leftX: Int16, leftY: Int16, rightX: Int16, rightY: Int16)
    -> [ControllerEvent]
  {
    var events: [ControllerEvent] = []
    if leftX != prevLX || leftY != prevLY {
      events.append(.leftStickChanged(x: normalizeAxis(leftX), y: normalizeAxis(leftY)))
    }
    if rightX != prevRX || rightY != prevRY {
      events.append(.rightStickChanged(x: normalizeAxis(rightX), y: normalizeAxis(rightY)))
    }
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

  private func readInt16LE(_ bytes: [UInt8], offset: Int) -> Int16 {
    let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    let value = Int16(bitPattern: raw)
    return value == Int16.min ? -Int16.max : value
  }

  private func clampedNegatedInt16LE(_ bytes: [UInt8], offset: Int) -> Int16 {
    -readInt16LE(bytes, offset: offset)
  }

  private func normalizeAxis(_ value: Int16) -> Float {
    let normalized = Float(value) / SteamControllerReportLayout.stickMax
    if abs(normalized) < SteamControllerReportLayout.deadzone { return 0 }
    return max(-1, min(1, normalized))
  }

  private func mapDpad(_ value: UInt8) -> DpadDirection {
    let up = (value & 0x01) != 0
    let right = (value & 0x02) != 0
    let left = (value & 0x04) != 0
    let down = (value & 0x08) != 0
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
