import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NintendoCalibrationTests {
  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func factoryReplyCalibratesAllThreeSamples(_ layout: NintendoControllerLayout) throws {
    let parser = SwitchProParser(layout: layout)
    let requests = parser.hidStartupReports(transport: "Bluetooth")
    #expect(Array(requests[3].bytes.suffix(6)) == [0x10, 0x20, 0x60, 0, 0, 24])
    #expect(Array(requests[4].bytes.suffix(6)) == [0x10, 0x26, 0x80, 0, 0, 20])
    #expect(try parser.parse(data: reply(), receivedAtNanoseconds: 1).isEmpty)
    let samples = try samples(parser)
    #expect(samples.count == 3)
    #expect(samples.map(\.timestamp.sequenceIndex) == [0, 1, 2])
    let right = layout == .rightJoyCon
    for sample in samples {
      #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 110, y: 220, z: 330))
      let reading = try #require(sample.physicalReading)
      #expect(reading.calibrationSource == .deviceFactory)
      #expect(reading.calibrationRevision == 1)
      #expect(reading.gyroscopeDegreesPerSecond
        == ControllerMotionVector(x: right ? 20 : -20, y: right ? -30 : 30, z: -10))
      #expect(reading.accelerationG
        == ControllerMotionVector(x: right ? 2 : -2, y: right ? -3 : 3, z: -1))
    }
  }

  @Test func unrelatedMalformedAndUnsolicitedRepliesCannotInstallCalibration() throws {
    let parser = SwitchProParser()
    _ = try parser.parse(data: reply())
    #expect(try samples(parser).first?.physicalReading?.calibrationSource == .nominalDeviceScale)
    _ = parser.hidStartupReports(transport: "USB")
    for offset in [13, 14, 15, 16, 17, 18, 19] {
      var invalid = reply()
      invalid[offset] = 0x7F
      _ = try parser.parse(data: invalid)
      #expect(try samples(parser).first?.physicalReading?.calibrationSource == .nominalDeviceScale)
    }
    _ = try parser.parse(data: reply().prefix(43))
    #expect(try samples(parser).first?.physicalReading?.calibrationSource == .nominalDeviceScale)
    var erased = reply()
    erased.replaceSubrange(20..<44, with: Array(repeating: UInt8(255), count: 24))
    _ = try parser.parse(data: erased)
    #expect(try samples(parser).first?.physicalReading?.calibrationSource == .nominalDeviceScale)
    _ = try parser.parse(data: reply())
    #expect(try samples(parser).first?.physicalReading?.calibrationSource == .deviceFactory)
  }

  private func reply() -> Data {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x21
    data[13] = 0x90
    data[14] = 0x10
    data[15] = 0x20
    data[16] = 0x60
    data[19] = 24
    for axis in 0..<3 {
      write(100, into: &data, at: 20 + axis * 2)
      write(16484, into: &data, at: 26 + axis * 2)
      let gyroOffset = Int16((axis + 1) * 10)
      write(gyroOffset, into: &data, at: 32 + axis * 2)
      write(gyroOffset + 9360, into: &data, at: 38 + axis * 2)
    }
    return data
  }

  @Test(arguments: [false, true])
  func userOffsetsCombineWithFactorySensitivityInEitherOrder(userFirst: Bool) throws {
    let parser = SwitchProParser()
    _ = parser.hidStartupReports(transport: "Bluetooth")
    let first = userFirst ? userReply() : reply()
    let second = userFirst ? reply() : userReply()
    _ = try parser.parse(data: first)
    #expect(try samples(parser).first?.physicalReading?.calibrationSource
      == (userFirst ? .nominalDeviceScale : .deviceFactory))
    _ = try parser.parse(data: second)
    let reading = try #require(samples(parser).first?.physicalReading)
    #expect(reading.calibrationSource == .factoryWithUserOffsets)
    #expect(reading.calibrationRevision == (userFirst ? 1 : 2))
    // User offsets equal the fixture's raw gyro readings, so the calibrated rotation is zero.
    #expect(reading.gyroscopeDegreesPerSecond == ControllerMotionVector(x: 0, y: 0, z: 0))
    #expect(reading.accelerationG == ControllerMotionVector(x: -4, y: 6, z: -2))
    #expect(try JSONDecoder().decode(
      ControllerMotionReading.self, from: JSONEncoder().encode(reading)
    ) == reading)
    // Duplicate replies cannot replace a completed acquisition's snapshot.
    _ = try parser.parse(data: userReply(invalid: true))
    #expect(try samples(parser).first?.physicalReading == reading)
  }

  @Test func invalidUserRangesRetainFactoryAndNewParserStartsNominal() throws {
    let parser = SwitchProParser()
    _ = parser.hidStartupReports(transport: "Bluetooth")
    _ = try parser.parse(data: reply())
    let factory = try #require(samples(parser).first?.physicalReading)
    _ = try parser.parse(data: userReply(invalid: true))
    #expect(try samples(parser).first?.physicalReading == factory)
    #expect(try samples(SwitchProParser()).first?.physicalReading?.calibrationSource
      == .nominalDeviceScale)
  }

  @Test func reacquisitionOnlyAdvancesForChangedCoefficients() throws {
    let parser = SwitchProParser()
    _ = parser.hidStartupReports(transport: "Bluetooth")
    _ = try parser.parse(data: reply())
    #expect(try samples(parser).first?.physicalReading?.calibrationRevision == 1)
    _ = parser.hidStartupReports(transport: "Bluetooth")
    _ = try parser.parse(data: reply())
    #expect(try samples(parser).first?.physicalReading?.calibrationRevision == 1)
    _ = parser.hidStartupReports(transport: "Bluetooth")
    var changed = reply()
    write(11, into: &changed, at: 32)
    _ = try parser.parse(data: changed)
    #expect(try samples(parser).first?.physicalReading?.calibrationRevision == 2)
  }

  @Test func recoveryOnlyRetriesPendingReadsAndExpiryRetainsAcceptedCalibration() throws {
    let parser = SwitchProParser()
    _ = parser.hidStartupReports(transport: "Bluetooth")
    let retry = parser.pendingHIDStartupReports()
    #expect(retry.count == 2)
    #expect(retry.map { $0.bytes[1] } == [5, 6])
    _ = try parser.parse(data: reply())
    let factory = try #require(samples(parser).first?.physicalReading)
    let remaining = parser.pendingHIDStartupReports()
    #expect(remaining.count == 1)
    #expect(Array(try #require(remaining.first).bytes.suffix(5)) == [0x26, 0x80, 0, 0, 20])
    parser.expireHIDStartupRequests()
    #expect(parser.pendingHIDStartupReports().isEmpty)
    _ = try parser.parse(data: userReply())
    #expect(try samples(parser).first?.physicalReading == factory)
    // A later explicit acquisition begins fresh and can combine both new replies.
    _ = parser.hidStartupReports(transport: "Bluetooth")
    _ = try parser.parse(data: userReply())
    #expect(try samples(parser).first?.physicalReading == factory)
    _ = try parser.parse(data: reply())
    #expect(try samples(parser).first?.physicalReading?.calibrationSource
      == .factoryWithUserOffsets)
  }

  @Test func pipelineStopExpiresOutstandingSPIReads() async {
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x057E, productID: 0x2009),
      transport: .hid(locationID: 84),
      parser: SwitchProParser(),
      dispatcher: LoggingOutputDispatcher()
    )
    await pipeline.start()
    _ = await pipeline.hidStartupOutputPlan(transport: "Bluetooth")
    #expect(await pipeline.pendingHIDStartupReports().count == 2)
    await pipeline.stop()
    await pipeline.start()
    #expect(await pipeline.pendingHIDStartupReports().isEmpty)
    await pipeline.stop()
  }

  private func userReply(invalid: Bool = false) -> Data {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x21
    data[13] = 0x90
    data[14] = 0x10
    data[15] = 0x26
    data[16] = 0x80
    data[19] = 20
    data[20] = 0xB2
    data[21] = 0xA1
    for axis in 0..<3 {
      write(invalid ? 16484 : 8292, into: &data, at: 22 + axis * 2)
      write(Int16((axis + 1) * 110), into: &data, at: 34 + axis * 2)
    }
    return data
  }

  private func samples(_ parser: SwitchProParser) throws -> [ControllerMotionSample] {
    var data = Data(repeating: 0, count: 49)
    data[0] = 0x30
    for index in 0..<3 {
      for axis in 0..<3 {
        write(Int16((axis + 1) * 4096), into: &data, at: 13 + index * 12 + axis * 2)
        write(Int16((axis + 1) * 110), into: &data, at: 19 + index * 12 + axis * 2)
      }
    }
    return try parser.parse(data: data, receivedAtNanoseconds: 100).compactMap {
      if case .motionSample(let sample) = $0 { return sample }
      return nil
    }
  }

  private func write(_ value: Int16, into data: inout Data, at offset: Int) {
    let raw = UInt16(bitPattern: value)
    data[offset] = UInt8(truncatingIfNeeded: raw)
    data[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
