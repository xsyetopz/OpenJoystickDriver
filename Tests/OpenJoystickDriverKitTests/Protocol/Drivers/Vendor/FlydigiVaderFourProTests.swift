import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Captured through a per-device input-report callback (issue #35, pull request #36), plus the
// rumble frame the reporter drove on the dongle. The hardware is the reporter's; none of ours has
// been tested.
private enum Capture {
  /// Dongle DInput `04B4:2412`: the neutral vendor report, 32 bytes, as PR #36 captured it.
  static let dongleNeutral: [UInt8] = [
    0x04, 0xFE, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x40, 0xFF,
    0xB5, 0x00, 0x7F, 0x00, 0x7F, 0x00, 0x7F, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0x00,
  ]

  /// Bluetooth XInput `045E:02E0`: the neutral report of issue #35, 16 bytes, report ID 1.
  static let bluetoothNeutral: [UInt8] = [
    0x01, 0x00, 0x7F, 0xFF, 0x7F, 0x00, 0x7F, 0xFF, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00,
  ]

  static func dongle(_ bytes: [Int: UInt8]) -> Data { patched(dongleNeutral, bytes) }

  static func bluetooth(_ bytes: [Int: UInt8]) -> Data { patched(bluetoothNeutral, bytes) }

  private static func patched(_ base: [UInt8], _ bytes: [Int: UInt8]) -> Data {
    var report = base
    for (offset, value) in bytes { report[offset] = value }
    return Data(report)
  }
}

@Suite
struct FlydigiVaderFourProDongleTests {
  private static let model = ControllerModelID(vendorID: 0x04B4, productID: 0x2412)

  private static func driver() throws -> ReportLayoutDriver {
    try #require(try catalogParser(model) as? ReportLayoutDriver)
  }

  @Test
  func capturedNeutralReportRestsCentred() throws {
    let state = try #require(try Self.driver().parseReport(Capture.dongle([:]))).state
    #expect(abs(state.leftStick.x.rawValue) < 300 && abs(state.rightStick.y.rawValue) < 300)
    #expect(state.leftTrigger.rawValue == 0 && state.rightTrigger.rawValue == 0)
  }

  @Test(arguments: [
    (8, UInt8(0x08), Control.guide), (9, 0x10, .south), (9, 0x20, .east), (9, 0x80, .west),
    (10, 0x01, .north), (10, 0x02, .start), (10, 0x04, .leftShoulder), (7, 0x01, .auxiliary1),
  ])
  func buttonsAndHomeDecode(offset: Int, mask: UInt8, control: Control) throws {
    let driver = try Self.driver()
    _ = try driver.parseReport(Capture.dongle([:]))
    #expect(try driver.parseReport(Capture.dongle([offset: mask])).contains(.press(control)))
  }

  @Test
  func sticksAndTriggersReadTheirBytes() throws {
    let state = try #require(
      try Self.driver().parseReport(Capture.dongle([17: 0xFF, 23: 0xFF, 24: 0x80]))
    ).state
    #expect(state.leftStick.x.rawValue > 32_000)
    #expect(state.leftTrigger.rawValue == UInt16.max)
    #expect(abs(Int(state.rightTrigger.rawValue) - 32_896) < 300)
  }

  /// The reporter drove the motors on a dongle: `05 0F <left> <right>` on report 5, resent at about
  /// 10 Hz, and stopped by the same frame with zero magnitudes.
  @Test
  func rumbleSendsVerifiedVendorFrameAndStopsWithSameCommand() throws {
    let driver = try Self.driver()
    let on = RumbleIntensities(
      lowFrequency: UnipolarValue(byte: 0x40),
      highFrequency: UnipolarValue(byte: 0x80)
    )
    let write = try #require(try driver.encode(.setRumble(on, duration: .held)).writes.first)
    guard case .hidOutput(let report) = write else { throw CatalogBindingFailure() }
    #expect(report.reportID == 0x05)
    #expect(report.bytes == [0x05, 0x0F, 0x40, 0x80])
    let stop = try #require(try driver.encode(.setRumble(.off, duration: .held)).writes.first)
    guard case .hidOutput(let off) = stop else { throw CatalogBindingFailure() }
    #expect(off.bytes == [0x05, 0x0F, 0x00, 0x00])
  }

  @Test
  func rumbleResentEveryHundredMilliseconds() throws {
    let plan = try Self.driver().sessionPlan
    #expect(plan.keepAliveChannels == [.hid])
    #expect(plan.keepAliveIntervalNanoseconds == 100_000_000)
  }
}

@Suite
struct FlydigiVaderFourProBluetoothXInputTests {
  private static let model = ControllerModelID(vendorID: 0x045E, productID: 0x02E0)

  private static func driver() throws -> ReportLayoutDriver {
    try #require(try catalogParser(model, host: .bluetoothClassic) as? ReportLayoutDriver)
  }

  /// Unsigned 16-bit axes centered at 0x7FFF: the neutral report is centered, 0xFFFF is full right
  /// and 0x0000 full left, where a signed read wraps everything above 0x8000 negative.
  @Test
  func unsignedAxesCentreAtSevenFFFAndReachBothEnds() throws {
    let driver = try Self.driver()
    let centred = try #require(try driver.parseReport(Capture.bluetooth([:]))).state
    #expect(abs(centred.leftStick.x.rawValue) < 300 && abs(centred.leftStick.y.rawValue) < 300)
    #expect(abs(centred.rightStick.x.rawValue) < 300 && abs(centred.rightStick.y.rawValue) < 300)
    let right = try #require(try driver.parseReport(Capture.bluetooth([1: 0xFF, 2: 0xFF]))).state
    #expect(right.leftStick.x.rawValue > 32_000)
    let left = try #require(try driver.parseReport(Capture.bluetooth([1: 0x00, 2: 0x00]))).state
    #expect(left.leftStick.x.rawValue < -32_000)
    let rightStick = try #require(try driver.parseReport(Capture.bluetooth([5: 0xFF, 6: 0xFF])))
    #expect(rightStick.state.rightStick.x.rawValue > 32_000)
  }

  @Test
  func triggersTenBitUnsigned() throws {
    let driver = try Self.driver()
    let full = try #require(
      try driver.parseReport(Capture.bluetooth([9: 0xFF, 10: 0x03, 11: 0xFF, 12: 0x03]))
    ).state
    #expect(full.leftTrigger.rawValue == UInt16.max && full.rightTrigger.rawValue == UInt16.max)
    let released = try #require(try driver.parseReport(Capture.bluetooth([:]))).state
    #expect(released.leftTrigger.rawValue == 0)
  }

  @Test(arguments: [
    (14, UInt8(0x01), Control.south), (14, 0x02, .east), (14, 0x04, .west), (14, 0x08, .north),
    (14, 0x10, .leftShoulder), (14, 0x20, .rightShoulder), (14, 0x40, .back), (14, 0x80, .start),
    (15, 0x01, .leftStickClick), (15, 0x02, .rightStickClick),
  ])
  func buttonsDecode(offset: Int, mask: UInt8, control: Control) throws {
    let driver = try Self.driver()
    _ = try driver.parseReport(Capture.bluetooth([:]))
    #expect(try driver.parseReport(Capture.bluetooth([offset: mask])).contains(.press(control)))
  }

  @Test(arguments: [
    (UInt8(1), HatDirection.north), (3, .east), (5, .south), (7, .west),
  ])
  func hatDecodes(value: UInt8, direction: HatDirection) throws {
    #expect(
      try Self.driver().parseReport(Capture.bluetooth([13: value])).contains(.hat(direction))
    )
  }

  /// Home arrives on report ID 2, byte 1 bit 0; the main report does not release it.
  @Test
  func homeArrivesOnReportTwoAndMainReportLeavesItAlone() throws {
    let driver = try Self.driver()
    _ = try driver.parseReport(Capture.bluetooth([:]))
    #expect(try driver.parseReport(Data([0x02, 0x01])).contains(.press(.guide)))
    #expect(try driver.parseReport(Capture.bluetooth([:])).contains(.release(.guide)) == false)
    #expect(try driver.parseReport(Data([0x02, 0x00])).contains(.release(.guide)))
  }
}
