import Foundation

/// USB feature and effect layouts consumed by SDL's PS4/PS5 HIDAPI drivers.
/// Calibration describes the virtual axes; these bytes are not a physical capture.
enum SonyUSBHostProtocol {
  static func setReport(
    _ request: VirtualHostReportRequest,
    dualSense: Bool
  ) throws -> VirtualHostReportResponse {
    let identifier: UInt8 = dualSense ? 0x02 : 0x05
    guard request.reportID == identifier else { throw VirtualHostReportError.unsupported }
    let expected = dualSense ? 47 : 31
    guard request.payload.count <= expected else { throw VirtualHostReportError.tooLarge }
    guard request.payload.count == expected else { throw VirtualHostReportError.malformed }
    let payload = request.payload
    if dualSense {
      let emulating = payload[0] & 0x01 != 0 || payload[38] & 0x04 != 0
      return VirtualHostReportResponse(
        rumble: VirtualRumbleCommand(
          left: emulating ? payload[3] : 0,
          right: emulating ? payload[2] : 0
        )
      )
    }
    guard payload[0] & 0x01 != 0 else { return VirtualHostReportResponse() }
    return VirtualHostReportResponse(
      rumble: VirtualRumbleCommand(left: payload[4], right: payload[3])
    )
  }

  static func featureReport(
    _ identifier: UInt8,
    dualSense: Bool,
    address: [UInt8]
  ) throws -> [UInt8] {
    let serialID: UInt8 = dualSense ? 0x09 : 0x12
    let calibrationID: UInt8 = dualSense ? 0x05 : 0x02
    if identifier == serialID {
      var report = [UInt8](repeating: 0, count: dualSense ? 20 : 16)
      report[0] = serialID
      report.replaceSubrange(1..<7, with: address.reversed())
      return report
    }
    if identifier == calibrationID {
      var report = [UInt8](repeating: 0, count: dualSense ? 41 : 37)
      report[0] = calibrationID
      // Zero biases; nonzero symmetric extrema keep consumer calibration denominators valid.
      for offset in [7, 11, 15] {
        write(16_000, into: &report, at: offset)
        write(-16_000, into: &report, at: offset + 2)
      }
      write(1_000, into: &report, at: 19)
      write(1_000, into: &report, at: 21)
      for offset in [23, 27, 31] {
        write(8_192, into: &report, at: offset)
        write(-8_192, into: &report, at: offset + 2)
      }
      return report
    }
    if dualSense, identifier == 0x20 {
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = identifier
      // Advertise the effect layout with improved rumble emulation understood by this codec.
      report[44] = 0x24
      report[45] = 0x02
      return report
    }
    throw VirtualHostReportError.unsupported
  }

  static func featureDescriptor(dualSense: Bool) -> [UInt8] {
    let reports: [(UInt8, UInt8)] =
      dualSense ? [(0x05, 40), (0x09, 19), (0x20, 63)] : [(0x02, 36), (0x12, 15)]
    return reports.flatMap { identifier, count in
      [0x06, 0x00, 0xFF, 0x85, identifier, 0x09, identifier, 0x75, 0x08, 0x95, count, 0xB1, 0x02]
    }
  }

  private static func write(_ value: Int16, into report: inout [UInt8], at offset: Int) {
    let bits = UInt16(bitPattern: value)
    report[offset] = UInt8(truncatingIfNeeded: bits)
    report[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
  }
}
