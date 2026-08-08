import Foundation
import SwiftUSB

private let steamControllerReportPrefix0: UInt8 = 0x01
private let steamControllerReportPrefix1: UInt8 = 0x00
private let steamControllerStateMessageID: UInt8 = 0x01
private let steamControllerWirelessMessageID: UInt8 = 0x03
private let steamControllerStatusMessageID: UInt8 = 0x04
private let steamControllerReportLength = 64
private let steamControllerTriggerMax: Float = 255
private let steamControllerStickMax: Float = 32767
private let steamControllerDeadzone: Float = 0.08
private let steamControllerWirelessDisconnected: UInt8 = 0x01
private let steamControllerWirelessConnected: UInt8 = 0x02
private let steamControllerSetDefaultDigitalMappingsCommand: UInt8 = 0x85
private let steamControllerLoadDefaultSettingsCommand: UInt8 = 0x8E
private let steamControllerClearDigitalMappingsCommand: UInt8 = 0x81
private let steamControllerSetSettingsValuesCommand: UInt8 = 0x87
private let steamControllerGetWirelessStateCommand: UInt8 = 0xB4
private let steamControllerHapticPulseCommand: UInt8 = 0x8F
private let steamControllerHapticPulsePayloadLength: UInt8 = 8
private let steamControllerUserLEDBrightnessSetting: UInt8 = 45
private let steamControllerMaximumPulseMicroseconds = 65_535
private let steamControllerTrackpadNone: UInt8 = 0x07
private let steamControllerLeftTrackpadModeSetting: UInt8 = 0x07
private let steamControllerRightTrackpadModeSetting: UInt8 = 0x08

/// Parser for Valve Steam Controller input reports.
///
/// Linux `hid-steam.c` receives 64-byte raw events prefixed with `0x01, 0x00`.
/// Message type `0x01` carries a 60-byte controller state payload with button
/// bytes at offsets 8-10, analog triggers at 11-12, left stick/left pad axes at
/// 16-19, and right pad axes at 20-23. Source-backed lizard-mode feature
/// reports are sent when OJD starts and stops consuming Steam Controller input.
public final class SteamControllerParser: InputParser, ControllerInputConnectionLifecycle,
  HIDInputConnectionStatusRequester, HIDStartupFeatureReportProvider,
  HIDShutdownFeatureReportProvider, PhysicalHIDFeatureHapticOutput,
  PhysicalHIDFeatureBrightnessOutput, @unchecked Sendable
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

  public var physicalRumbleMotors: [PhysicalRumbleMotor] { [.leftHaptic, .rightHaptic] }

  public var requiresInputConnectionBeforeOutput: Bool { isWirelessReceiver }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingConnectionStateChange
    pendingConnectionStateChange = nil
    return state
  }

  public func hidStartupFeatureReports() -> [PhysicalHIDOutputReport] {
    [
      steamFeatureReport([steamControllerClearDigitalMappingsCommand]),
      steamFeatureReport([
        steamControllerSetSettingsValuesCommand, 6, steamControllerLeftTrackpadModeSetting,
        steamControllerTrackpadNone, 0, steamControllerRightTrackpadModeSetting,
        steamControllerTrackpadNone, 0,
      ]),
    ]
  }

  public func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport] {
    [
      steamFeatureReport([steamControllerSetDefaultDigitalMappingsCommand]),
      steamFeatureReport([steamControllerLoadDefaultSettingsCommand]),
    ]
  }

  public func physicalBrightnessReport(_ brightness: UInt8) -> PhysicalHIDOutputReport {
    steamFeatureReport([
      steamControllerSetSettingsValuesCommand, 3, steamControllerUserLEDBrightnessSetting,
      brightness, 0,
    ])
  }

  public func physicalHapticReports(left: UInt8, right: UInt8, durationMs: Int)
    -> [PhysicalHIDOutputReport]
  {
    guard isLogicalControllerConnected else { return [] }
    let effectiveDurationMs = durationMs > 0 ? min(durationMs, 5_000) : 65
    let totalMicroseconds = max(1, effectiveDurationMs * 1_000)
    let pulseDuration = min(totalMicroseconds, steamControllerMaximumPulseMicroseconds)
    let pulseCount = min(65_535, (totalMicroseconds + pulseDuration - 1) / pulseDuration)
    var reports: [PhysicalHIDOutputReport] = []
    if left > 0 {
      reports.append(
        hapticPulseReport(
          pad: 1,
          intensity: left,
          durationMicroseconds: pulseDuration,
          count: pulseCount
        )
      )
    }
    if right > 0 {
      reports.append(
        hapticPulseReport(
          pad: 0,
          intensity: right,
          durationMicroseconds: pulseDuration,
          count: pulseCount
        )
      )
    }
    return reports
  }

  public func inputConnectionStatusRequestReport() -> PhysicalHIDOutputReport? {
    guard isWirelessReceiver else { return nil }
    return steamFeatureReport([steamControllerGetWirelessStateCommand])
  }

  /// No-op for the current experimental input slice.
  public func performHandshake(handle: USBDeviceHandle?) async throws { await Task.yield() }

  /// Parses one Steam Controller state report and returns controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = Array(data)
    guard bytes.count == steamControllerReportLength, bytes[0] == steamControllerReportPrefix0,
      bytes[1] == steamControllerReportPrefix1
    else { return [] }

    switch bytes[ReportOffset.messageType] {
    case steamControllerWirelessMessageID:
      parseWirelessStatus(bytes)
      return []
    case steamControllerStatusMessageID:
      parseWirelessStatusFallback()
      return []
    case steamControllerStateMessageID:
      guard isLogicalControllerConnected else { return [] }
      return parseControllerState(bytes)
    default: return []
    }
  }

  private func parseWirelessStatus(_ bytes: [UInt8]) {
    guard isWirelessReceiver else { return }
    let nextConnected: Bool
    switch bytes[ReportOffset.wirelessStatus] {
    case steamControllerWirelessDisconnected: nextConnected = false
    case steamControllerWirelessConnected: nextConnected = true
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

  private func hapticPulseReport(
    pad: UInt8,
    intensity: UInt8,
    durationMicroseconds: Int,
    count: Int
  ) -> PhysicalHIDOutputReport {
    let gainDecibels = -24 + Int((Double(intensity) * 30.0 / 255.0).rounded())
    let gain = UInt8(bitPattern: Int8(clamping: gainDecibels))
    return steamFeatureReport([
      steamControllerHapticPulseCommand, steamControllerHapticPulsePayloadLength, pad,
      UInt8(truncatingIfNeeded: durationMicroseconds),
      UInt8(truncatingIfNeeded: durationMicroseconds >> 8), 0, 0, UInt8(truncatingIfNeeded: count),
      UInt8(truncatingIfNeeded: count >> 8), gain,
    ])
  }

  private func steamFeatureReport(_ command: [UInt8]) -> PhysicalHIDOutputReport {
    var report = [UInt8](repeating: 0, count: steamControllerReportLength)
    for (index, byte) in command.prefix(steamControllerReportLength).enumerated() {
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
      events.append(.leftTriggerChanged(Float(left) / steamControllerTriggerMax))
    }
    if right != prevRT {
      events.append(.rightTriggerChanged(Float(right) / steamControllerTriggerMax))
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
    let normalized = Float(value) / steamControllerStickMax
    if abs(normalized) < steamControllerDeadzone { return 0 }
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
