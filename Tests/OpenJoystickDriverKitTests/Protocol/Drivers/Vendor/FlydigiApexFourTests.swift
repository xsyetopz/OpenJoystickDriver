import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Reports built from the layout of the pinned protocol notes for the Apex 4 in DInput mode, not
/// captured from a pad: report ID 4 in byte 0, 32 bytes, sticks centered at `0x7F`.
private enum SourceReport {
  static let model = ControllerModelID(vendorID: 0x04B4, productID: 0x2412)

  static var neutral: [UInt8] {
    var report = [UInt8](repeating: 0, count: 32)
    report[0] = 0x04
    report[1] = 0xFE
    for offset in [17, 19, 21, 22] { report[offset] = 0x7F }
    return report
  }

  static func with(_ bytes: [Int: UInt8]) -> Data {
    var report = neutral
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

@Suite
struct FlydigiApexFourTests {
  private static func driver() throws -> ReportLayoutDriver {
    try #require(try catalogParser(SourceReport.model) as? ReportLayoutDriver)
  }

  @Test(arguments: [
    (7, UInt8(0x01), Control.auxiliary1), (7, 0x02, .auxiliary2), (7, 0x04, .leftPaddle1),
    (7, 0x08, .leftPaddle2), (7, 0x10, .rightPaddle1), (7, 0x20, .rightPaddle2),
    (8, 0x08, .guide), (9, 0x10, .south), (9, 0x20, .east), (9, 0x40, .back), (9, 0x80, .west),
    (10, 0x01, .north), (10, 0x02, .start), (10, 0x04, .leftShoulder), (10, 0x08, .rightShoulder),
    (10, 0x40, .leftStickClick), (10, 0x80, .rightStickClick),
  ])
  func buttonBitsPressAndRelease(offset: Int, mask: UInt8, button: Control) throws {
    let driver = try Self.driver()
    _ = try driver.parseReport(SourceReport.with([:]))
    let pressed = try driver.parseReport(SourceReport.with([offset: mask]))
    #expect(pressed.contains(.press(button)))
    #expect(try driver.parseReport(SourceReport.with([:])).contains(.release(button)))
  }

  @Test(arguments: [
    (UInt8(0x01), HatDirection.north), (0x02, .east), (0x04, .south), (0x08, .west),
  ])
  func directionBitsMoveHat(mask: UInt8, direction: HatDirection) throws {
    let driver = try Self.driver()
    #expect(try driver.parseReport(SourceReport.with([9: mask])).contains(.hat(direction)))
  }

  /// Sticks center at `0x7F`, and a low raw Y is up, as in the notes.
  @Test
  func sticksAndTriggersReadTheirBytes() throws {
    let driver = try Self.driver()
    let centred = try #require(try driver.parseReport(SourceReport.with([:]))).state
    #expect(abs(centred.leftStick.x.rawValue) < 300)
    let moved = try #require(
      try driver.parseReport(SourceReport.with([17: 0xFF, 19: 0x00, 23: 0xFF, 24: 0x80]))
    ).state
    #expect(moved.leftStick.x.rawValue > 32_000)
    #expect(moved.leftStick.y.rawValue < -32_000)
    #expect(moved.leftTrigger.rawValue == UInt16.max)
    #expect(abs(Int(moved.rightTrigger.rawValue) - 32_896) < 300)
  }

  /// A digital trigger bit reads as a fully pulled trigger.
  @Test(arguments: [(UInt8(0x10), true), (0x20, false)])
  func digitalTriggerBitsPullTrigger(mask: UInt8, left: Bool) throws {
    let driver = try Self.driver()
    let state = try #require(try driver.parseReport(SourceReport.with([10: mask]))).state
    #expect((left ? state.leftTrigger : state.rightTrigger).rawValue == UInt16.max)
  }

  @Test
  func otherReportsAreIgnored() throws {
    let driver = try Self.driver()
    var reply = SourceReport.neutral
    reply[0] = 0x05
    #expect(try driver.parseReport(Data(reply)) == nil)
    #expect(try driver.parseReport(Data(SourceReport.neutral.dropLast())) == nil)
  }
}
