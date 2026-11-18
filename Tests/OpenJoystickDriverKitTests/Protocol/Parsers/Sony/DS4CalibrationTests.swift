import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DS4CalibrationTests {
  @Test
  func onlyChangedAcceptedCoefficientsAdvanceRevision() throws {
    let parser = DualShock4Driver()
    let request = try #require(parser.startupFeatureReads().first)
    #expect(try motion(parser).calibrationRevision == 0)
    var data = factory(bluetooth: false)
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 1)
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 1)
    write(21, into: &data, at: 1)
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 2)
    data[0] = 0
    #expect(!parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 2)
  }

  @Test(arguments: [false, true])
  func factoryCalibrationUsesTransportLayout(bluetooth: Bool) throws {
    let parser = DualShock4Driver(prefersBluetooth: bluetooth)
    let requests = parser.startupFeatureReads()
    #expect(requests.map(\.reportID) == (bluetooth ? [5] : [2]))
    let request = try #require(requests.last)
    let data = factory(bluetooth: bluetooth)
    #expect(parser.consumeFeatureReply(data, request: request))
    let sample = try motion(parser)
    // Calibrated sensor axes (1, 1, 1) °/s and (1, -1, 0) g land canonical as (x, -z, y).
    #expect(sample.calibrationSource == .deviceFactory)
    #expect(isClose(sample.angularVelocity, radiansPerSecond(1, -1, 1)))
    #expect(isClose(sample.acceleration, metresPerSecondSquared(1, 0, -1)))
    var invalid = data
    invalid[24] = 0
    #expect(!parser.consumeFeatureReply(invalid, request: request))
    let retained = try motion(parser)
    #expect(retained.angularVelocity == sample.angularVelocity)
    #expect(retained.acceleration == sample.acceleration)
    #expect(retained.calibrationRevision == sample.calibrationRevision)
    #expect(!parser.consumeFeatureReply(data.dropLast(), request: request))
  }

  @Test
  func bluetoothModeReplyCannotInstallUSBLayout() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)
    let requests = parser.startupFeatureReads()
    #expect(requests.map(\.reportID) == [5])
    #expect(!parser.consumeFeatureReply(factory(bluetooth: false), request: requests[0]))
    #expect(try motion(parser).calibrationSource == .nominalDeviceScale)
    var corrupted = factory(bluetooth: true)
    corrupted[40] ^= 1
    #expect(!parser.consumeFeatureReply(corrupted, request: requests[0]))
    #expect(try motion(parser).calibrationSource == .nominalDeviceScale)
  }

  @Test
  func thirdPartyControllerKeepsNominalScaleAfterValidFactoryReport() throws {
    let parser = DualShock4Driver(usesFactoryCalibration: false)
    let request = try #require(parser.startupFeatureReads().first)
    #expect(parser.consumeFeatureReply(factory(bluetooth: false), request: request))
    let sample = try motion(parser)
    #expect(sample.calibrationSource == .nominalDeviceScale)
    #expect(sample.calibrationRevision == 0)
  }

  @Test
  func registryInstallsFactoryCalibrationOnlyForSonyVendorID() throws {
    let sony = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x054C, productID: 0x05C4)) as? DualShock4Driver
    )
    let hori = try #require(
      try catalogParser(ControllerModelID(vendorID: 0x0F0D, productID: 0x0055)) as? DualShock4Driver
    )
    #expect(sony.usesFactoryCalibration)
    #expect(!hori.usesFactoryCalibration)
  }

  private func motion(_ parser: DualShock4Driver) throws -> ControllerMotionSample {
    var data = Data(repeating: 0, count: 64)
    data[0] = 1
    for (index, value) in [Int16(36), -10, 64].enumerated() {
      write(value, into: &data, at: 13 + index * 2)
    }
    for (index, value) in [Int16(8292), -8092, 100].enumerated() {
      write(value, into: &data, at: 19 + index * 2)
    }
    return try #require(parser.parseReport(data)?.motion.first)
  }

  private func factory(bluetooth: Bool) -> Data {
    var data = Data(repeating: 0, count: bluetooth ? 41 : 37)
    data[0] = bluetooth ? 5 : 2
    for (index, bias) in [Int16(20), -30, 40].enumerated() {
      write(bias, into: &data, at: 1 + index * 2)
      let endpoint = Int16(8000 + index * 2000)
      write(endpoint, into: &data, at: 7 + index * (bluetooth ? 2 : 4))
      write(-endpoint, into: &data, at: bluetooth ? 13 + index * 2 : 9 + index * 4)
      write(8292, into: &data, at: 23 + index * 4)
      write(-8092, into: &data, at: 25 + index * 4)
    }
    write(500, into: &data, at: 19)
    write(500, into: &data, at: 21)
    if bluetooth {
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in [UInt8(0xA3)] + Array(data.prefix(37)) {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
      }
      crc = ~crc
      for index in 0..<4 { data[37 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    }
    return data
  }

  private func write(_ value: Int16, into data: inout Data, at offset: Int) {
    let raw = UInt16(bitPattern: value)
    data[offset] = UInt8(truncatingIfNeeded: raw)
    data[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
