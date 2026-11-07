import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A Wii driver fed reports at a clock the test advances, with every output report it writes
/// logged at the time it was written.
final class WiiSession {
  static let calibrationBlock: [UInt8] = [
    0x80, 0x82, 0x84, 0b00_01_10_11, 0xC0, 0xC2, 0xC4, 0b00_11_10_01, 0, 0,
  ]
  static let tick: UInt64 = 10_000_000

  let driver: WiiDriver
  private(set) var clock: UInt64 = 0
  private(set) var log: [(at: UInt64, report: [UInt8])] = []

  init(irFormat: ProtocolDescription.WiiRemote.BlockKind? = .irBasic) {
    driver = WiiDriver(tuning: nil, irFormat: irFormat)
    driver.setPointerInputWanted(irFormat != nil)
  }

  /// Parses `report` at the clock and logs the writes it queued.
  @discardableResult
  func feed(_ report: [UInt8]) throws -> ControllerEvent? {
    let event = try driver.parseReport(Data(report), at: clock)
    note(driver.drainPendingWrites())
    return event
  }

  func feed(fixture: String) throws {
    try feed(Array(WiiFixtures.report(fixture)))
  }

  /// Logs `writes` as written at the clock.
  func note(_ writes: [PhysicalOutputWrite]) {
    for case .hidOutput(let report) in writes { log.append((clock, report.bytes)) }
  }

  func advance(by nanoseconds: UInt64 = WiiSession.tick) { clock += nanoseconds }

  /// Reads the first status report and the calibration block; the IR setup's first write follows
  /// when IR is requested.
  func startUp() throws {
    try feed(fixture: "20-status-no-extension")
    advance(by: 1_000_000)
    let block = Self.calibrationBlock
    let padded = block + [UInt8](repeating: 0, count: 16 - block.count)
    try feed([0x21, 0, 0, UInt8(block.count - 1) << 4, 0x00, 0x16] + padded)
  }

  /// Acknowledges every step the moment it is written and keeps reports flowing until the log
  /// holds `count` writes after `from`.
  func answer(from: Int, count: Int) throws {
    var acknowledged = from
    while log.count < from + count && clock < 2_000_000_000 {
      if acknowledged < log.count {
        try feed([0x22, 0, 0, log[acknowledged].report[0], 0])
        acknowledged += 1
      } else {
        advance()
        try feed([0x30, 0, 0])
      }
    }
    if acknowledged < log.count { try feed([0x22, 0, 0, log[acknowledged].report[0], 0]) }
  }
}
