import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Sony's wireless adapter and the STRIKEPAD grip follow SDL `SDL_hidapi_ps4.c`.
extension DualShock4DriverTests {
  private static let calibrationRequest = PhysicalHIDFeatureReadRequest(reportID: 2, length: 37)

  private static func at(_ milliseconds: UInt64) -> MonotonicTimestamp {
    MonotonicTimestamp(nanoseconds: milliseconds * 1_000_000)
  }

  /// A USB report with SDL's no-pad flag, bit 2 of `data[31]` (payload byte 30, after battery).
  private static func noPadReport(buttons0: UInt8 = 0x08) -> Data {
    var report = makeDS4Report(buttons0: buttons0)
    report[31] |= 0x04
    return report
  }

  /// A USB calibration report whose gyro endpoints are valid only in the Bluetooth order
  /// (all plus endpoints, then all minus endpoints).
  private static func groupedGyroCalibration() -> Data {
    var report = [UInt8](repeating: 0, count: 37)
    report[0] = 0x02
    func put(_ value: Int16, at offset: Int) {
      let bits = UInt16(bitPattern: value)
      report[offset] = UInt8(truncatingIfNeeded: bits)
      report[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
    }
    // Gyro Y is all on its minus side, so the interleaved order reads half the X range.
    let gyroPlus: [Int16] = [8_640, 0, 8_640]
    let gyroMinus: [Int16] = [-8_640, -17_280, -8_640]
    for index in 0..<3 {
      put(gyroPlus[index], at: 7 + index * 2)
      put(gyroMinus[index], at: 13 + index * 2)
      put(8_192, at: 23 + index * 4)
      put(-8_192, at: 25 + index * 4)
    }
    put(540, at: 19)
    put(540, at: 21)
    return Data(report)
  }

  @Test
  func modelFollowsSDLProductIDs() {
    #expect(DualShock4Model(vendorID: 0x054C, productID: 0x0BA0) == .wirelessAdapter)
    #expect(DualShock4Model(vendorID: 0x054C, productID: 0x05C5) == .strikePad)
    #expect(DualShock4Model(vendorID: 0x054C, productID: 0x09CC) == .standard)
  }

  @Test
  func adapterWaitsForAPadBeforeOutput() {
    #expect(
      DualShock4Driver(model: .wirelessAdapter).sessionPlan.requiresInputConnectionBeforeOutput
    )
    #expect(!DualShock4Driver().sessionPlan.requiresInputConnectionBeforeOutput)
  }

  @Test
  func adapterConnectsOnPadReportsAndIgnoresNoPadReports() throws {
    let driver = DualShock4Driver(model: .wirelessAdapter)
    let noPad = Self.noPadReport(buttons0: 0x28)
    #expect(try driver.parse(report: noPad, receivedAt: Self.at(0)) == nil)
    #expect(driver.consumeInputConnectionStateChange() == nil)

    let pad = makeDS4Report(buttons0: 0x28)
    #expect(try driver.parseReport(pad, at: 10_000_000).contains(.press(.faceSouth)))
    #expect(driver.consumeInputConnectionStateChange() == .connected)
    #expect(driver.consumeInputConnectionStateChange() == nil)
  }

  @Test
  func adapterDisconnectsAfterHalfASecondOfNoPadReports() throws {
    let driver = DualShock4Driver(model: .wirelessAdapter)
    _ = try driver.parse(report: makeDS4Report(), receivedAt: Self.at(0))
    #expect(driver.consumeInputConnectionStateChange() == .connected)

    let noPad = Self.noPadReport()
    _ = try driver.parse(report: noPad, receivedAt: Self.at(499))
    #expect(driver.consumeInputConnectionStateChange() == nil)
    _ = try driver.parse(report: noPad, receivedAt: Self.at(500))
    #expect(driver.consumeInputConnectionStateChange() == .disconnected)
    _ = try driver.parse(report: noPad, receivedAt: Self.at(900))
    #expect(driver.consumeInputConnectionStateChange() == nil)

    _ = try driver.parse(report: makeDS4Report(), receivedAt: Self.at(1_000))
    #expect(driver.consumeInputConnectionStateChange() == .connected)
  }

  @Test
  func standardPadIgnoresTheAdapterStatusBit() throws {
    let driver = DualShock4Driver()
    let report = Self.noPadReport(buttons0: 0x28)
    #expect(try driver.parse(report: report, receivedAt: Self.at(0)) != nil)
    #expect(driver.consumeInputConnectionStateChange() == nil)
  }

  @Test
  func adapterReadsUSBCalibrationInTheBluetoothGyroOrder() {
    let reply = Self.groupedGyroCalibration()
    let adapter = DualShock4Driver(model: .wirelessAdapter)
    #expect(adapter.consumeFeatureReply(reply, request: Self.calibrationRequest))
    #expect(!DualShock4Driver().consumeFeatureReply(reply, request: Self.calibrationRequest))
  }

  @Test
  func strikePadDoublesGyroAndNegatesDoubledAccel() throws {
    let timestamp = ControllerSampleTimestamp(
      rawCounter: 0,
      monotonic: MonotonicTimestamp(nanoseconds: 0),
      tickNanosecondsNumerator: nil,
      tickNanosecondsDenominator: nil,
      sequenceIndex: 0,
      basis: .hostEstimate
    )
    let raw = ControllerRawSensorVector(x: 160, y: 0, z: 0)
    func sample(_ driver: DualShock4Driver) throws -> ControllerMotionSample {
      try #require(driver.motionCalibration.sample(timestamp: timestamp, gyro: raw, accel: raw))
    }

    let standard = try sample(DualShock4Driver())
    for strikePad in [DualShock4Driver(model: .strikePad), calibrated(.strikePad)] {
      let scaled = try sample(strikePad)
      #expect(abs(scaled.angularVelocity.x - 2 * standard.angularVelocity.x) < 1e-9)
      #expect(abs(scaled.acceleration.x + 2 * standard.acceleration.x) < 1e-9)
    }
  }

  private func calibrated(_ model: DualShock4Model) -> DualShock4Driver {
    let driver = DualShock4Driver(model: model)
    var reply = Array(Self.groupedGyroCalibration())
    // Interleaved gyro endpoints (plus, minus per axis) for a standard USB pad.
    for index in 0..<3 {
      reply[7 + index * 4] = 0xC0
      reply[8 + index * 4] = 0x21
      reply[9 + index * 4] = 0x40
      reply[10 + index * 4] = 0xDE
    }
    #expect(driver.consumeFeatureReply(Data(reply), request: Self.calibrationRequest))
    return driver
  }
}
