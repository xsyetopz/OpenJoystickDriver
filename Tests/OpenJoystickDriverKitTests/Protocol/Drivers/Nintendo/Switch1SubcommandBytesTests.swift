import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct Switch1SubcommandBytesTests {
  private func hex(_ write: PhysicalOutputWrite) -> String {
    guard case .hidOutput(let report) = write else { return "other" }
    return "\(report.reportID):" + report.bytes.map { unsafe String(format: "%02x", $0) }.joined()
  }

  private func sequence(_ driver: Switch1Driver) throws -> [String] {
    var lines = driver.startupWrites().map(hex)
    lines += driver.startupRecoveryWrites().map(hex)
    let rumble = RumbleIntensities(
      lowFrequency: UnipolarValue(200 << 8),
      highFrequency: UnipolarValue(90 << 8)
    )
    lines += try driver.encode(.setRumble(rumble, duration: .milliseconds(200))).writes.map(hex)
    for indicator in [
      PhysicalPlayerIndicator.player1, .player2, .player3, .player4, .off,
    ] {
      lines += try driver.encode(.setPlayerIndicator(indicator)).writes.map(hex)
    }
    for _ in 0..<10 { lines += try driver.encode(.stopRumble).writes.map(hex) }
    return lines
  }

  /// The bytes of each report as `reportID:hex`, captured before the subcommands came from the
  /// description: startup, a recovery round, a rumble, the player indicators, and ten stop-rumble
  /// reports that carry the counter past its wrap.
  private static let proUSB = [
    "1:010000014040000140400330",
    "1:010100014040000140404001",
    "1:010200014040000140404801",
    "1:01030001404000014040102060000018",
    "1:01040001404000014040102680000014",
    "1:01050001404000014040102060000018",
    "1:01060001404000014040102680000014",
    "16:100700b3c06d0069405a",
    "1:010800b3c06d0069405a3001",
    "1:010900b3c06d0069405a3003",
    "1:010a00b3c06d0069405a3007",
    "1:010b00b3c06d0069405a300f",
    "1:010c00b3c06d0069405a3000",
    "16:100d0001404000014040",
    "16:100e0001404000014040",
    "16:100f0001404000014040",
    "16:10000001404000014040",
    "16:10010001404000014040",
    "16:10020001404000014040",
    "16:10030001404000014040",
    "16:10040001404000014040",
    "16:10050001404000014040",
    "16:10060001404000014040",
  ]

  private static let leftJoyConBluetooth = [
    "1:010000014040000140400330",
    "1:010100014040000140404001",
    "1:010200014040000140404801",
    "1:01030001404000014040102060000018",
    "1:01040001404000014040102680000014",
    "1:01050001404000014040102060000018",
    "1:01060001404000014040102680000014",
    "16:100700b3c06d00014040",
    "1:010800b3c06d000140403001",
    "1:010900b3c06d000140403003",
    "1:010a00b3c06d000140403007",
    "1:010b00b3c06d00014040300f",
    "1:010c00b3c06d000140403000",
    "16:100d0001404000014040",
    "16:100e0001404000014040",
    "16:100f0001404000014040",
    "16:10000001404000014040",
    "16:10010001404000014040",
    "16:10020001404000014040",
    "16:10030001404000014040",
    "16:10040001404000014040",
    "16:10050001404000014040",
    "16:10060001404000014040",
  ]

  @Test
  func testProSubcommandBytesAreUnchanged() throws {
    #expect(try sequence(Switch1Driver()) == Self.proUSB)
  }

  @Test
  func testLeftJoyConSubcommandBytesAreUnchanged() throws {
    let driver = Switch1Driver(layout: .leftJoyCon, isBluetooth: true)
    #expect(try sequence(driver) == Self.leftJoyConBluetooth)
  }
}
