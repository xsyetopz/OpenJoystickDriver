import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The `37D7:2401` record's startup writes and extended `5A A5 EF` report.
///
/// Both are source-derived from the pinned openflydigi notes. No dongle has received the writes or
/// sent the report.
struct FlydigiVaderFiveProTests {
  private static let model = ControllerModelID(vendorID: 0x37D7, productID: 0x2401)

  /// The bytes of an output report after its ID 3, zero-padded to the 32-byte report.
  private static func frame(_ bytes: [UInt8]) -> [UInt8] {
    bytes + [UInt8](repeating: 0, count: 31 - bytes.count)
  }

  private static func driver() throws -> ReportLayoutDriver {
    try #require(try catalogParser(model) as? ReportLayoutDriver)
  }

  @Test
  func theRecordSendsTheThreeInitWritesThenTheTestModeWrite() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.model))
    #expect(
      record.startupWrites.map(\.bytes) == [
        Self.frame([0x5A, 0xA5, 0x01, 0x02, 0x03]),
        Self.frame([0x5A, 0xA5, 0xA1, 0x02, 0xA3]),
        Self.frame([0x5A, 0xA5, 0x02, 0x02, 0x04]),
        Self.frame([0x5A, 0xA5, 0x11, 0x07, 0xFF, 0x01, 0xFF, 0xFF, 0xFF, 0x15]),
      ]
    )
  }

  /// A startup frame is `5A A5 cmd len payload sum`, with len the payload length plus 2 and sum
  /// the low byte of cmd, len and payload.
  @Test
  func everyStartupWriteEndsWithItsChecksum() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.model))
    #expect(!record.startupWrites.isEmpty)
    for write in record.startupWrites {
      #expect(write.report.reportID == 3)
      #expect(write.bytes.count == 31)
      let payloadEnd = 2 + Int(write.bytes[3])
      let sum = write.bytes[2..<payloadEnd].reduce(UInt8(0), &+)
      #expect(Array(write.bytes[0..<2]) == [0x5A, 0xA5])
      #expect(write.bytes[payloadEnd] == sum)
      #expect(write.bytes[(payloadEnd + 1)...].allSatisfy { $0 == 0 })
    }
  }

  private static func report(_ bytes: [Int: UInt8]) -> Data {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...2] = [0x5A, 0xA5, 0xEF]
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }

  @Test
  func sticksAndTriggersReadTheirOffsets() throws {
    let driver = try Self.driver()
    let moved: [Int: UInt8] = [
      3: 0xFF, 4: 0x7F, 5: 0x00, 6: 0x80, 7: 0xFF, 8: 0x7F, 9: 0x00, 10: 0x80, 15: 0xFF, 16: 0x80,
    ]
    let state = try #require(try driver.parseReport(Self.report(moved))).state
    #expect(state.leftStick.x.rawValue > 32_000)
    #expect(state.leftStick.y.rawValue < -32_000)
    #expect(state.rightStick.x.rawValue > 32_000)
    #expect(state.rightStick.y.rawValue < -32_000)
    #expect(state.leftTrigger.rawValue == UInt16.max)
    #expect(abs(Int(state.rightTrigger.rawValue) - 32_896) < 300)
  }

  @Test
  func aShortReportIsIgnored() throws {
    let driver = try Self.driver()
    #expect(try driver.parseReport(Data(Self.report([:]).dropLast())) == nil)
  }
}
