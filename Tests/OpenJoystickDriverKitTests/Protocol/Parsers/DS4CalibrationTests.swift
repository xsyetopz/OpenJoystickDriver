import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DS4CalibrationTests {
  @Test func onlyChangedAcceptedCoefficientsAdvanceRevision() throws {
    let parser = DS4Parser()
    let request = try #require(parser.hidStartupFeatureReadRequests().first)
    #expect(try motion(parser).physicalReading?.calibrationRevision == 0)
    var data = factory(bluetooth: false)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 1)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 1)
    write(21, into: &data, at: 1)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 2)
    data[0] = 0
    #expect(!parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 2)
  }

  @Test(arguments: [false, true])
  func factoryCalibrationUsesTransportLayout(bluetooth: Bool) throws {
    let parser = DS4Parser(prefersBluetooth: bluetooth)
    let requests = parser.hidStartupFeatureReadRequests()
    #expect(requests.map(\.reportID) == (bluetooth ? [2, 5] : [2]))
    let request = try #require(requests.last)
    let data = factory(bluetooth: bluetooth)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: nil))
    let sample = try motion(parser)
    #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 36, y: -10, z: 64))
    let reading = try #require(sample.physicalReading)
    #expect(reading.calibrationSource == .deviceFactory)
    #expect(reading.gyroscopeDegreesPerSecond == ControllerMotionVector(x: 1, y: 1, z: 1))
    #expect(reading.accelerationG == ControllerMotionVector(x: 1, y: -1, z: 0))
    var invalid = data
    invalid[24] = 0
    #expect(!parser.consumeHIDFeatureReport(invalid, request: request, transport: nil))
    #expect(try motion(parser).physicalReading == reading)
    #expect(!parser.consumeHIDFeatureReport(data.dropLast(), request: request, transport: nil))
  }

  @Test func bluetoothModeReplyCannotInstallUSBLayout() throws {
    let parser = DS4Parser()
    let requests = parser.hidStartupFeatureReadRequests(transport: "Bluetooth")
    #expect(requests.map(\.reportID) == [2, 5])
    #expect(parser.consumeHIDFeatureReport(
      factory(bluetooth: false), request: requests[0], transport: "Bluetooth"
    ))
    #expect(try motion(parser).physicalReading?.calibrationSource == .nominalDeviceScale)
    var corrupted = factory(bluetooth: true)
    corrupted[40] ^= 1
    #expect(!parser.consumeHIDFeatureReport(
      corrupted, request: requests[1], transport: "Bluetooth"
    ))
    #expect(try motion(parser).physicalReading?.calibrationSource == .nominalDeviceScale)
  }

  private func motion(_ parser: DS4Parser) throws -> ControllerMotionSample {
    var data = Data(repeating: 0, count: 64)
    data[0] = 1
    for (index, value) in [Int16(36), -10, 64].enumerated() {
      write(value, into: &data, at: 13 + index * 2)
    }
    for (index, value) in [Int16(8292), -8092, 100].enumerated() {
      write(value, into: &data, at: 19 + index * 2)
    }
    return try #require(parser.parse(data: data).compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
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
