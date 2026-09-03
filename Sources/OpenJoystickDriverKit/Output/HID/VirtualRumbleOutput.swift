import Foundation
import IOKit.hid

public struct VirtualRumbleCommand: Equatable, Sendable {
  public static let defaultDurationMs = 250

  public let left: UInt8
  public let right: UInt8
  public let leftTrigger: UInt8
  public let rightTrigger: UInt8
  public let durationMs: Int

  public init(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    durationMs: Int = Self.defaultDurationMs
  ) {
    self.left = left
    self.right = right
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.durationMs = durationMs
  }
}

public enum VirtualRumbleOutputReportParser {
  public static let xboxOneReportID: UInt8 = 3
  public static let xboxOneReportPayloadSize = 8
  public static let xboxGIPReportID: UInt8 = 9
  public static let xboxGIPReportPayloadSizeWithoutReportID = 12

  private static let xboxOneReportTypeByte: UInt8 = 0x03
  private static let xbox360RumbleHeader8Byte: UInt8 = 0x00
  private static let xbox360RumbleHeaderByte: UInt8 = 0x08
  private static let ojdRumbleMarker: UInt8 = 0x4F
  private static let rumbleActivationAllMotors: UInt8 = 0x0F
  private static let rumbleActivationLeftTrigger: UInt8 = 0x01
  private static let rumbleActivationRightTrigger: UInt8 = 0x02
  private static let rumbleActivationLeft: UInt8 = 0x04
  private static let rumbleActivationRight: UInt8 = 0x08
  private static let rumbleDurationByteMultiplier = 10

  public static func parse(type: IOHIDReportType, reportID: UInt32, bytes: [UInt8])
    -> VirtualRumbleCommand?
  {
    guard type == kIOHIDReportTypeOutput || type == kIOHIDReportTypeFeature else { return nil }

    if let command = parseXboxOneReport(reportID: reportID, bytes: bytes) { return command }
    if let command = parseXboxGIPReport(reportID: reportID, bytes: bytes) { return command }
    if let command = parseXbox360Report(reportID: reportID, bytes: bytes) { return command }
    if let command = parseOJDReport(reportID: reportID, bytes: bytes) { return command }
    return nil
  }

  private static func parseXboxOneReport(reportID: UInt32, bytes: [UInt8]) -> VirtualRumbleCommand?
  {
    let payload: [UInt8]
    if reportID == UInt32(xboxOneReportID) {
      payload =
        bytes.count >= xboxOneReportPayloadSize + 1 && bytes.first == xboxOneReportID
        ? Array(bytes.dropFirst()) : bytes
    } else if reportID == 0, bytes.first == Self.xboxOneReportTypeByte {
      payload = Array(bytes.dropFirst())
    } else {
      return nil
    }
    guard payload.count >= 5 else { return nil }
    let activation = payload[0] & Self.rumbleActivationAllMotors
    let leftTrigger = (activation & Self.rumbleActivationLeftTrigger) != 0 ? payload[1] : 0
    let rightTrigger = (activation & Self.rumbleActivationRightTrigger) != 0 ? payload[2] : 0
    let left = (activation & Self.rumbleActivationLeft) != 0 ? payload[3] : 0
    let right = (activation & Self.rumbleActivationRight) != 0 ? payload[4] : 0
    let duration =
      payload.count >= 6
      ? Int(payload[5]) * Self.rumbleDurationByteMultiplier : VirtualRumbleCommand.defaultDurationMs
    return VirtualRumbleCommand(
      left: left,
      right: right,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger,
      durationMs: max(0, duration)
    )
  }

  private static func parseXboxGIPReport(reportID: UInt32, bytes: [UInt8]) -> VirtualRumbleCommand?
  {
    let payload: [UInt8]
    if reportID == UInt32(xboxGIPReportID) {
      let normalized =
        bytes.count >= xboxGIPReportPayloadSizeWithoutReportID + 1 && bytes.first == xboxGIPReportID
        ? Array(bytes.dropFirst()) : bytes
      payload =
        normalized.first == GIPCommand.rumble ? normalized : [GIPCommand.rumble] + normalized
    } else if reportID == 0, bytes.first == GIPCommand.rumble {
      payload = bytes
    } else {
      return nil
    }
    guard payload.count >= 10, payload[0] == GIPCommand.rumble else { return nil }

    let activation = payload[5] & Self.rumbleActivationAllMotors
    let leftTrigger = (activation & Self.rumbleActivationLeftTrigger) != 0 ? payload[6] : 0
    let rightTrigger = (activation & Self.rumbleActivationRightTrigger) != 0 ? payload[7] : 0
    let left = (activation & Self.rumbleActivationLeft) != 0 ? payload[8] : 0
    let right = (activation & Self.rumbleActivationRight) != 0 ? payload[9] : 0
    let duration =
      payload.count >= 11
      ? Int(payload[10]) * Self.rumbleDurationByteMultiplier
      : VirtualRumbleCommand.defaultDurationMs
    return VirtualRumbleCommand(
      left: left,
      right: right,
      leftTrigger: leftTrigger,
      rightTrigger: rightTrigger,
      durationMs: max(0, duration)
    )
  }

  private static func parseXbox360Report(reportID: UInt32, bytes: [UInt8]) -> VirtualRumbleCommand?
  {
    let payload: [UInt8]
    guard reportID == 0 else { return nil }
    payload = bytes

    if payload.count >= 8, payload[0] == Self.xbox360RumbleHeader8Byte,
      payload[1] == Self.xbox360RumbleHeaderByte
    {
      return VirtualRumbleCommand(left: payload[3], right: payload[4])
    }
    if payload.count >= 4, payload[0] == Self.xbox360RumbleHeaderByte {
      return VirtualRumbleCommand(left: payload[2], right: payload[3])
    }
    return nil
  }

  private static func parseOJDReport(reportID: UInt32, bytes: [UInt8]) -> VirtualRumbleCommand? {
    guard reportID == 0, bytes.first == Self.ojdRumbleMarker else { return nil }
    let payload = Array(bytes.dropFirst())
    guard payload.count >= 4 else { return nil }
    let duration: Int
    if payload.count >= 6 {
      duration = Int(UInt16(payload[4]) | (UInt16(payload[5]) << 8))
    } else {
      duration = VirtualRumbleCommand.defaultDurationMs
    }
    return VirtualRumbleCommand(
      left: payload[0],
      right: payload[1],
      leftTrigger: payload[2],
      rightTrigger: payload[3],
      durationMs: duration
    )
  }
}
