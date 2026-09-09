import Foundation
import IOKit.hid

/// Mutable host state belongs to one published device, never to its shared report format.
final class VirtualHostProtocolSession: @unchecked Sendable {
  private let lock = NSLock()
  private let format: any VirtualGamepadReportFormat
  private let address: [UInt8]
  private var nintendo = NintendoUSBHostProtocol()
  private var closed = false

  init(format: any VirtualGamepadReportFormat) {
    self.format = format
    var uuid = UUID().uuid
    // A locally administered unicast address identifies this virtual session only.
    address = withUnsafeBytes(of: &uuid) { [0x02] + Array($0.prefix(5)) }
  }

  func close() { lock.withLock { closed = true } }

  func setReport(_ request: VirtualHostReportRequest) throws -> VirtualHostReportResponse {
    try lock.withLock {
      guard !closed else { throw VirtualHostReportError.closed }
      guard request.type == .output else { throw VirtualHostReportError.unsupported }
      if format is DualShock4USBHIDReportFormat {
        return try SonyUSBHostProtocol.setReport(request, dualSense: false)
      }
      if format is DualSenseUSBHIDReportFormat {
        return try SonyUSBHostProtocol.setReport(request, dualSense: true)
      }
      if format is SwitchProUSBHIDReportFormat {
        return try nintendo.setReport(request, address: address)
      }
      return try standardOutput(request)
    }
  }

  /// Returns a bounded complete report, including its ID when the format declares one.
  func getReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    maxSize: Int,
    currentInput: [UInt8]
  ) throws -> [UInt8] {
    try lock.withLock {
      guard !closed else { throw VirtualHostReportError.closed }
      guard maxSize > 0, let identifier = UInt8(exactly: reportID) else {
        throw VirtualHostReportError.malformed
      }
      let report: [UInt8]
      if type == .input, identifier == format.inputReportID ?? 0 {
        report = currentInput
      } else if type == .feature, format is DualShock4USBHIDReportFormat {
        report = try SonyUSBHostProtocol.featureReport(
          identifier,
          dualSense: false,
          address: address
        )
      } else if type == .feature, format is DualSenseUSBHIDReportFormat {
        report = try SonyUSBHostProtocol.featureReport(
          identifier,
          dualSense: true,
          address: address
        )
      } else {
        throw VirtualHostReportError.unsupported
      }
      return Array(report.prefix(maxSize))
    }
  }

  private func standardOutput(
    _ request: VirtualHostReportRequest
  ) throws -> VirtualHostReportResponse {
    guard let maximum = format.outputReportPayloadSize,
      request.reportID == format.outputReportID ?? 0
    else { throw VirtualHostReportError.unsupported }
    guard request.payload.count <= maximum else { throw VirtualHostReportError.tooLarge }
    let length = request.payload.count
    switch request.reportID {
    case VirtualRumbleOutputReportParser.xboxOneReportID:
      guard length == VirtualRumbleOutputReportParser.xboxOneReportPayloadSize else {
        throw VirtualHostReportError.malformed
      }
    case VirtualRumbleOutputReportParser.xboxGIPReportID:
      guard length == VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID else {
        throw VirtualHostReportError.malformed
      }
    case 0:
      let validLength: Bool
      switch request.payload.first {
      case 0: validLength = length == 8
      case 8: validLength = length == 4 || length == 7
      case 0x4F: validLength = length == 5 || length == 7
      default: validLength = false
      }
      guard validLength else { throw VirtualHostReportError.malformed }
    default: throw VirtualHostReportError.unsupported
    }
    guard
      let command = VirtualRumbleOutputReportParser.parse(
        type: kIOHIDReportTypeOutput,
        reportID: UInt32(request.reportID),
        bytes: request.completeReport
      )
    else { throw VirtualHostReportError.malformed }
    return VirtualHostReportResponse(rumble: command)
  }
}
