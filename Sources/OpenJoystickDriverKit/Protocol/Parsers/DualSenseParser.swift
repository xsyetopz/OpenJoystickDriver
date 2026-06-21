import Foundation
import SwiftUSB

private let dualSenseAxisCenter: Float = 128
private let dualSenseAxisPositiveMax: Float = 127
private let dualSenseAxisNegativeMax: Float = 128
private let dualSenseAxisDeadzone: Float = 0.08
private let dualSenseHatNeutral: UInt8 = 0xFF
private let dualSenseTriggerMax: Float = 255
private let dualSenseUSBInputReportID: UInt8 = 0x01
private let dualSenseUSBInputReportLength = 64
private let dualSenseBluetoothInputReportID: UInt8 = 0x31
private let dualSenseBluetoothInputReportLength = 78
private let dualSenseBluetoothHIDInputTransaction: UInt8 = 0xA1
private let dualSenseInputCRC32Seed: UInt8 = 0xA1

public enum DualSenseParserError: Error, Equatable {
  case invalidBluetoothCRC
}

/// Parser for Sony DualSense controllers.
///
/// USB report ID `0x01` follows Linux `hid-playstation.c`'s
/// `struct dualsense_input_report`: four stick axes, two trigger axes,
/// sequence number, then button bytes, including the mic-mute button as a
/// generic experimental button. Bluetooth report `0x31` carries the same
/// common input report after its two-byte header and is accepted only when
/// its Linux-compatible CRC32 validates.
public final class DualSenseParser: InputParser, @unchecked Sendable {

  private enum ReportOffset {
    static let leftStickX = 0
    static let leftStickY = 1
    static let rightStickX = 2
    static let rightStickY = 3
    static let l2Trigger = 4
    static let r2Trigger = 5
    static let buttons0 = 7
    static let buttons1 = 8
    static let buttons2 = 9
  }

  private var prevFace: UInt8 = 0
  private var prevShoulders: UInt8 = 0
  private var prevSystem: UInt8 = 0
  private var prevHat: UInt8 = dualSenseHatNeutral
  private var prevL2: UInt8 = 0
  private var prevR2: UInt8 = 0
  private var prevLSX = UInt8(dualSenseAxisCenter)
  private var prevLSY = UInt8(dualSenseAxisCenter)
  private var prevRSX = UInt8(dualSenseAxisCenter)
  private var prevRSY = UInt8(dualSenseAxisCenter)

  /// Creates a new DualSense parser.
  public init() {}

  /// No-op for the current experimental HID input slice.
  public func performHandshake(handle: USBDeviceHandle?) async throws {
    await Task.yield()
  }

  /// Parses one DualSense HID input report and returns controller events.
  public func parse(data: Data) throws -> [ControllerEvent] {
    let bytes = try reportPayload(from: data)
    guard bytes.count >= 10 else { return [] }
    var events: [ControllerEvent] = []

    let stickEvents = parseSticks(bytes: bytes)
    events.append(contentsOf: stickEvents.events)
    let (lsxRaw, lsyRaw, rsxRaw, rsyRaw) = stickEvents.raws

    let triggerEvents = parseTriggers(bytes: bytes)
    events.append(contentsOf: triggerEvents.events)
    let (l2, r2) = triggerEvents.values

    let dpadEvents = parseDpad(bytes: bytes)
    events.append(contentsOf: dpadEvents.events)
    let hat = dpadEvents.value

    let faceEvents = parseFaceButtons(bytes: bytes)
    events.append(contentsOf: faceEvents.events)
    let face = faceEvents.value

    let shoulderEvents = parseShoulderButtons(bytes: bytes)
    events.append(contentsOf: shoulderEvents.events)
    let shoulders = shoulderEvents.value

    let systemEvents = parseSystemButtons(bytes: bytes)
    events.append(contentsOf: systemEvents.events)
    let system = systemEvents.value

    prevFace = face
    prevShoulders = shoulders
    prevSystem = system
    prevHat = hat
    prevL2 = l2
    prevR2 = r2
    prevLSX = lsxRaw
    prevLSY = lsyRaw
    prevRSX = rsxRaw
    prevRSY = rsyRaw

    return events
  }

  private func reportPayload(from data: Data) throws -> [UInt8] {
    let bytes = Array(data)
    if bytes.first == dualSenseUSBInputReportID, bytes.count >= dualSenseUSBInputReportLength {
      return Array(bytes.dropFirst())
    }
    if bytes.first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength
    {
      try validateBluetoothCRC(report: bytes)
      return Array(bytes.dropFirst(2).dropLast(4))
    }
    if bytes.first == dualSenseBluetoothHIDInputTransaction,
      bytes.dropFirst().first == dualSenseBluetoothInputReportID,
      bytes.count >= dualSenseBluetoothInputReportLength + 1
    {
      let report = Array(bytes.dropFirst())
      try validateBluetoothCRC(report: report)
      return Array(report.dropFirst(2).dropLast(4))
    }
    return []
  }

  private func validateBluetoothCRC(report: [UInt8]) throws {
    let expectedOffset = report.count - 4
    let expected = UInt32(report[expectedOffset])
      | (UInt32(report[expectedOffset + 1]) << 8)
      | (UInt32(report[expectedOffset + 2]) << 16)
      | (UInt32(report[expectedOffset + 3]) << 24)
    guard dualSenseBluetoothCRC32(report: report) == expected else {
      throw DualSenseParserError.invalidBluetoothCRC
    }
  }

  private func dualSenseBluetoothCRC32(report: [UInt8]) -> UInt32 {
    var crc = updateCRC32(0xFFFF_FFFF, byte: dualSenseInputCRC32Seed)
    for byte in report.dropLast(4) {
      crc = updateCRC32(crc, byte: byte)
    }
    return ~crc
  }

  private func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
    var crc = current ^ UInt32(byte)
    for _ in 0..<8 {
      if crc & 1 == 1 {
        crc = (crc >> 1) ^ 0xEDB8_8320
      } else {
        crc >>= 1
      }
    }
    return crc
  }

  private func parseSticks(bytes: [UInt8]) -> (
    events: [ControllerEvent], raws: (UInt8, UInt8, UInt8, UInt8)
  ) {
    let lsxRaw = bytes[ReportOffset.leftStickX]
    let lsyRaw = bytes[ReportOffset.leftStickY]
    let rsxRaw = bytes[ReportOffset.rightStickX]
    let rsyRaw = bytes[ReportOffset.rightStickY]
    var events: [ControllerEvent] = []
    if lsxRaw != prevLSX || lsyRaw != prevLSY {
      events.append(.leftStickChanged(x: normalizeHID(lsxRaw), y: -normalizeHID(lsyRaw)))
    }
    if rsxRaw != prevRSX || rsyRaw != prevRSY {
      events.append(.rightStickChanged(x: normalizeHID(rsxRaw), y: -normalizeHID(rsyRaw)))
    }
    return (events, (lsxRaw, lsyRaw, rsxRaw, rsyRaw))
  }

  private func parseTriggers(bytes: [UInt8])
    -> (events: [ControllerEvent], values: (UInt8, UInt8))
  {
    let l2 = bytes[ReportOffset.l2Trigger]
    let r2 = bytes[ReportOffset.r2Trigger]
    var events: [ControllerEvent] = []
    if l2 != prevL2 {
      events.append(.leftTriggerChanged(Float(l2) / dualSenseTriggerMax))
    }
    if r2 != prevR2 {
      events.append(.rightTriggerChanged(Float(r2) / dualSenseTriggerMax))
    }
    return (events, (l2, r2))
  }

  private func parseDpad(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let hat = bytes[ReportOffset.buttons0] & 0x0F
    var events: [ControllerEvent] = []
    if hat != prevHat { events.append(.dpadChanged(mapHat(hat))) }
    return (events, hat)
  }

  private func parseFaceButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let face = bytes[ReportOffset.buttons0]
    let events = diffButtons(
      prev: prevFace,
      curr: face,
      mapping: [(0x10, .square), (0x20, .cross), (0x40, .circle), (0x80, .triangle)]
    )
    return (events, face)
  }

  private func parseShoulderButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let shoulders = bytes[ReportOffset.buttons1]
    let events = diffButtons(
      prev: prevShoulders,
      curr: shoulders,
      mapping: [
        (0x01, .l1), (0x02, .r1), (0x04, .l2Digital), (0x08, .r2Digital), (0x10, .share),
        (0x20, .options), (0x40, .leftStick), (0x80, .rightStick),
      ]
    )
    return (events, shoulders)
  }

  private func parseSystemButtons(bytes: [UInt8]) -> (events: [ControllerEvent], value: UInt8) {
    let system = bytes[ReportOffset.buttons2]
    let events = diffButtons(
      prev: prevSystem,
      curr: system,
      mapping: [(0x01, .ps), (0x02, .touchpad), (0x04, .genericButton1)]
    )
    return (events, system)
  }

  private func normalizeHID(_ raw: UInt8) -> Float {
    let centered = Float(raw) - dualSenseAxisCenter
    let divisor = centered >= 0 ? dualSenseAxisPositiveMax : dualSenseAxisNegativeMax
    let normalized = centered / divisor
    if abs(normalized) < dualSenseAxisDeadzone { return 0 }
    return max(-1, min(1, normalized))
  }

  private func mapHat(_ hat: UInt8) -> DpadDirection {
    switch hat {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }

  private func diffButtons(
    prev: UInt8, curr: UInt8, mapping: [(UInt8, Button)]
  ) -> [ControllerEvent] {
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
}
