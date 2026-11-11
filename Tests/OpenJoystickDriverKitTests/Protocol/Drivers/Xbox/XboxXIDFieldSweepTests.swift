import CryptoKit
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Pins the `XboxXID` description's layout to every value of each field it reads.
///
/// `Tests/XIDFieldGolden/xid-field-sweep.txt` holds the frames that the Linux `xpad`
/// `XTYPE_XBOX` formulas give for a neutral 20-byte report with one field changed: every value of
/// bytes 2 and 4 to 11, and every 16-bit word of the four stick words at bytes 12, 14, 16 and 18.
/// A byte value renders as one line, so a changed byte names the value that moved. The 262,144
/// stick-word frames render as one SHA-256 of 256 lines for each high byte of each word, so the
/// golden stays small and a changed formula still names the word and high byte that moved.
struct XboxXIDFieldSweepTests {
  typealias Parse = (Data) throws -> ControllerState?

  static let byteOffsets = [2, 4, 5, 6, 7, 8, 9, 10, 11]
  static let wordOffsets = [12, 14, 16, 18]
  static let goldenFile = EquivalenceSnapshotStore.directory.deletingLastPathComponent()
    .appendingPathComponent("XIDFieldGolden/xid-field-sweep.txt")

  private static func report(_ changes: [(offset: Int, value: UInt8)]) -> Data {
    var bytes = [UInt8](repeating: 0, count: 20)
    for change in changes { bytes[change.offset] = change.value }
    return Data(bytes)
  }

  /// The golden's lines for the frames `parse` returns; a report it ignores renders `ignored`.
  static func render(_ parse: Parse) throws -> [String] {
    let renderer = DriverParseCharacterizationTests()
    func line(_ data: Data) throws -> String {
      try parse(data).map(renderer.render) ?? "ignored"
    }
    var lines = ["## bytes"]
    for offset in byteOffsets {
      for value in 0...255 {
        let rendered = try line(report([(offset, UInt8(value))]))
        lines.append("b\(offset)=\(hex(value)) \(rendered)")
      }
    }
    lines.append("## words")
    for offset in wordOffsets {
      for high in 0...255 {
        var block = ""
        for low in 0...255 {
          block += try line(report([(offset, UInt8(low)), (offset + 1, UInt8(high))])) + "\n"
        }
        let digest = SHA256.hash(data: Data(block.utf8)).map { hex(Int($0)) }.joined()
        lines.append("w\(offset) high=\(hex(high)) \(digest)")
      }
    }
    return lines
  }

  private static func hex(_ value: Int) -> String {
    let digits = String(value, radix: 16)
    return digits.count == 1 ? "0" + digits : digits
  }

  @Test
  func theDescribedLayoutDecodesEveryFieldValueAsTheGoldenRecords() throws {
    let driver = ReportLayoutDriver(
      describedBy: .xboxXID,
      variant: .gamepad,
      rumbleTemplate: nil,
      outEndpoint: 0x02,
      tuning: nil
    )
    let receivedAt = MonotonicTimestamp(nanoseconds: DriverParseCharacterizationTests.receivedAt)
    let actual = try Self.render { driver.parse(report: $0, receivedAt: receivedAt)?.state }
    let expected = try String(contentsOf: Self.goldenFile, encoding: .utf8)
      .split(separator: "\n").map(String.init)
    #expect(actual.count == expected.count)
    for (index, pair) in zip(actual, expected).enumerated() where pair.0 != pair.1 {
      Issue.record("line \(index + 1): \(pair.0) != \(pair.1)")
      break
    }
  }
}
