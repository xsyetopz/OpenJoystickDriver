import Foundation

/// USB initialization and SPI layout consumed by SDL's Switch HIDAPI driver.
struct NintendoUSBHostProtocol {
  private var vibrationEnabled = false
  private var imuEnabled = false
  private var playerLights: UInt8 = 0
  private var homeLight: [UInt8] = []

  mutating func setReport(
    _ request: VirtualHostReportRequest,
    address: [UInt8]
  ) throws -> VirtualHostReportResponse {
    let payload = request.payload
    guard payload.count <= 63 else { throw VirtualHostReportError.tooLarge }
    if request.reportID == 0x80 {
      guard let command = payload.first else { throw VirtualHostReportError.malformed }
      guard (1...5).contains(command) else { throw VirtualHostReportError.unsupported }
      // Force/Clear USB affect a hardware timeout; the virtual USB connection has no such timer.
      if command >= 4 { return VirtualHostReportResponse() }
      var report = [UInt8](repeating: 0, count: 64)
      report[0] = 0x81
      report[1] = command
      if command == 1 {
        report[3] = 3
        report.replaceSubrange(4..<10, with: address)
      }
      return VirtualHostReportResponse(inputReport: report)
    }
    guard request.reportID == 0x01 || request.reportID == 0x10 else {
      throw VirtualHostReportError.unsupported
    }
    guard payload.count >= (request.reportID == 0x01 ? 10 : 9),
      let left = SwitchProRumbleCodec.decodeIntensity(payload[1..<5]),
      let right = SwitchProRumbleCodec.decodeIntensity(payload[5..<9])
    else { throw VirtualHostReportError.malformed }
    var next = self
    var reply: [UInt8]?
    if request.reportID == 0x01 {
      reply = try next.subcommand(payload[9], data: Array(payload.dropFirst(10)), address: address)
    }
    let rumble = VirtualRumbleCommand(
      left: next.vibrationEnabled ? left : 0,
      right: next.vibrationEnabled ? right : 0
    )
    self = next
    return VirtualHostReportResponse(inputReport: reply, rumble: rumble)
  }

  private mutating func subcommand(
    _ command: UInt8,
    data: [UInt8],
    address: [UInt8]
  ) throws -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x21
    report[2] = 0x91
    SwitchProHIDBits.writeStick(x: 0, y: 0, into: &report, at: 6)
    SwitchProHIDBits.writeStick(x: 0, y: 0, into: &report, at: 9)
    report[13] = 0x80
    report[14] = command
    switch command {
    case 0x02:
      report[13] = 0x82
      report[15] = 4
      report[17] = 3
      report.replaceSubrange(19..<25, with: address)
      report[26] = 1  // Factory colors are present in virtual SPI.
    case 0x03: guard data.first == 0x30 else { throw VirtualHostReportError.unsupported }
    case 0x10:
      guard data.count >= 5, data[4] > 0, data[4] <= 29 else {
        throw VirtualHostReportError.malformed
      }
      let offset =
        UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
      let bytes = try Self.flashBytes(address: offset, length: Int(data[4]))
      report[13] = 0x90
      report.replaceSubrange(15..<20, with: data.prefix(5))
      report.replaceSubrange(20..<(20 + bytes.count), with: bytes)
    case 0x30:
      guard let value = data.first else { throw VirtualHostReportError.malformed }
      playerLights = value
    case 0x38:
      guard data.count >= 4 else { throw VirtualHostReportError.malformed }
      homeLight = Array(data.prefix(4))
    case 0x40, 0x48:
      guard let value = data.first, value <= 1 else { throw VirtualHostReportError.malformed }
      if command == 0x40 { imuEnabled = value == 1 } else { vibrationEnabled = value == 1 }
    case 0x41:
      guard data.count >= 4, data[0] <= 3, data[1] <= 3, data[2] <= 1, data[3] <= 1 else {
        throw VirtualHostReportError.malformed
      }
    default: throw VirtualHostReportError.unsupported
    }
    return report
  }

  /// Two explicit virtual flash pages. Unwritten bytes are erased (0xFF), not unknown replies.
  private static func flashBytes(address: UInt32, length: Int) throws -> [UInt8] {
    let page: [UInt8]
    let base: UInt32
    if address >= 0x6000, address < 0x6100 {
      base = 0x6000
      page = factoryFlash
    } else if address >= 0x8000, address < 0x8100 {
      base = 0x8000
      page = [UInt8](repeating: 0xFF, count: 256)
    } else {
      throw VirtualHostReportError.unsupported
    }
    let offset = Int(address - base)
    guard offset + length <= page.count else { throw VirtualHostReportError.malformed }
    return Array(page[offset..<(offset + length)])
  }

  private static let factoryFlash: [UInt8] = {
    var bytes = [UInt8](repeating: 0xFF, count: 256)
    // Virtual IMU origins and scales: accelerometer +/-8g, gyroscope +/-2000 degrees/s.
    bytes.replaceSubrange(0x20..<0x38, with: [UInt8](repeating: 0, count: 24))
    for offset in [0x26, 0x28, 0x2A] {
      bytes[offset] = 0x00
      bytes[offset + 1] = 0x40
    }
    for offset in [0x32, 0x34, 0x36] {
      bytes[offset] = 0x3B
      bytes[offset + 1] = 0x34
    }
    bytes.replaceSubrange(0x3D..<0x4F, with: SwitchProHIDBits.factoryStickCalibration())
    bytes.replaceSubrange(0x50..<0x5C, with: [UInt8](repeating: 0x32, count: 12))
    return bytes
  }()
}
