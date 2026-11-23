import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The `37D7:2401` record's startup writes and extended `5A A5 EF` report.
///
/// Synthetic reports use the layout documented in `docs/testing/flydigi-vader-5-pro.md`.
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
  func recordSendsThreeInitWritesThenTestModeWrite() throws {
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
    #expect(state.leftStick.y.rawValue > 32_000)
    #expect(state.rightStick.x.rawValue > 32_000)
    #expect(state.rightStick.y.rawValue > 32_000)
    #expect(state.leftTrigger.rawValue == UInt16.max)
    #expect(abs(Int(state.rightTrigger.rawValue) - 32_896) < 300)
  }

  @Test
  func standardAndExtraButtonsPressAndRelease() throws {
    let driver = try Self.driver()
    let buttons: [(offset: Int, mask: UInt8, control: Control)] = [
      (11, 0x10, .south), (11, 0x20, .east), (11, 0x40, .back), (11, 0x80, .west),
      (12, 0x01, .north), (12, 0x02, .start), (12, 0x04, .leftShoulder), (12, 0x08, .rightShoulder),
      (12, 0x40, .leftStickClick), (12, 0x80, .rightStickClick),
      (13, 0x01, .auxiliary1), (13, 0x02, .auxiliary2),
      (13, 0x04, .leftPaddle1), (13, 0x08, .rightPaddle1),
      (13, 0x10, .leftPaddle2), (13, 0x20, .rightPaddle2),
      (13, 0x40, .auxiliary3), (13, 0x80, .auxiliary4), (14, 0x08, .guide),
    ]
    for (offset, mask, control) in buttons {
      #expect(try driver.parseReport(Self.report([offset: mask]))?.state.pressed == [control])
      #expect(try driver.parseReport(Self.report([:]))?.state.pressed.isEmpty == true)
    }
  }

  @Test
  func directionalBitsProduceHatDirections() throws {
    let driver = try Self.driver()
    let directions: [(UInt8, HatDirection)] = [
      (0x01, .north), (0x02, .east), (0x04, .south), (0x08, .west),
      (0x03, .northEast), (0x06, .southEast), (0x0C, .southWest), (0x09, .northWest),
    ]
    for (mask, direction) in directions {
      #expect(try driver.parseReport(Self.report([11: mask]))?.state.hat == direction)
      #expect(try driver.parseReport(Self.report([:]))?.state.hat == HatDirection.neutral)
    }
  }

  @Test
  func shortReportIsIgnored() throws {
    let driver = try Self.driver()
    #expect(try driver.parseReport(Data(Self.report([:]).dropLast())) == nil)
  }
}
