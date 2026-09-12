import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DualSenseCalibrationTests {
  private let request = PhysicalHIDFeatureReadRequest(reportID: 5, length: 41)

  @Test func revisionChangesOnlyForNewAcceptedCoefficients() throws {
    let parser = DualSenseParser()
    var data = factory()
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 1)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 1)
    write(21, into: &data, at: 1)
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "USB"))
    #expect(try motion(parser).physicalReading?.calibrationRevision == 2)
  }

  @Test func legacyReadingDefaultsRevisionAndNewRevisionRoundTrips() throws {
    let parser = DualSenseParser()
    #expect(parser.consumeHIDFeatureReport(factory(), request: request, transport: "USB"))
    let reading = try #require(motion(parser).physicalReading)
    let encoded = try JSONEncoder().encode(reading)
    #expect(try JSONDecoder().decode(ControllerMotionReading.self, from: encoded) == reading)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "calibrationRevision")
    let legacy = try JSONDecoder().decode(
      ControllerMotionReading.self, from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(legacy.calibrationRevision == 0)
    #expect(legacy.gyroscopeDegreesPerSecond == reading.gyroscopeDegreesPerSecond)
  }

  @Test func nominalUnitsRetainRawReadings() throws {
    let sample = try motion(DualSenseParser(), gyro: [16, -16, 0], accel: [8192, 0, -8192])
    #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 16, y: -16, z: 0))
    let reading = try #require(sample.physicalReading)
    #expect(reading.calibrationSource == .nominalDeviceScale)
    #expect(reading.gyroscopeDegreesPerSecond == ControllerMotionVector(x: 1, y: -1, z: 0))
    #expect(reading.accelerationG == ControllerMotionVector(x: 1, y: 0, z: -1))
  }

  @Test func acceptedFactoryReportAppliesBiasAndScaleAtomically() throws {
    let parser = DualSenseParser()
    #expect(parser.consumeHIDFeatureReport(factory(), request: request, transport: "USB"))
    let zero = try motion(parser, gyro: [20, -30, 40], accel: [100, 100, 100])
    let reading = try #require(zero.physicalReading)
    #expect(reading.calibrationSource == .deviceFactory)
    #expect(reading.gyroscopeDegreesPerSecond == ControllerMotionVector(x: 0, y: 0, z: 0))
    #expect(reading.accelerationG == ControllerMotionVector(x: 0, y: 0, z: 0))
    let endpoint = try motion(parser, gyro: [36, -14, 56], accel: [8292, -8092, 100])
    #expect(endpoint.physicalReading?.gyroscopeDegreesPerSecond
      == ControllerMotionVector(x: 1, y: 1, z: 1))
    #expect(endpoint.physicalReading?.accelerationG == ControllerMotionVector(x: 1, y: -1, z: 0))
    var invalid = factory()
    invalid[24] = 0
    #expect(!parser.consumeHIDFeatureReport(invalid, request: request, transport: "USB"))
    let retained = try motion(parser, gyro: [20, -30, 40], accel: [100, 100, 100])
    #expect(retained.physicalReading == reading)
  }

  @Test func bluetoothCalibrationRequiresFeatureCRC() throws {
    let parser = DualSenseParser(prefersBluetooth: true)
    #expect(!parser.consumeHIDFeatureReport(factory(), request: request, transport: "Bluetooth"))
    var data = factory()
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in [UInt8(0xA3)] + Array(data.prefix(37)) {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
    }
    crc = ~crc
    for index in 0..<4 { data[37 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    #expect(parser.consumeHIDFeatureReport(data, request: request, transport: "Bluetooth"))
    #expect(try motion(parser).physicalReading?.calibrationSource == .deviceFactory)
  }

  @Test func stoppedPipelineRejectsCalibrationReplies() async throws {
    let parser = DualSenseParser()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x054C, productID: 0x0CE6),
      transport: .hid(locationID: 1),
      parser: parser,
      dispatcher: LoggingOutputDispatcher()
    )
    #expect(await pipeline.consumeHIDFeatureReport(
      factory(), request: request, transport: "USB"
    ) == false)
    await pipeline.start()
    #expect(await pipeline.consumeHIDFeatureReport(factory(), request: request, transport: "USB"))
    await pipeline.stop()
    #expect(await pipeline.consumeHIDFeatureReport(
      factory(), request: request, transport: "USB"
    ) == false)
  }

  private func motion(
    _ parser: DualSenseParser, gyro: [Int16] = [0, 0, 0], accel: [Int16] = [0, 0, 0]
  ) throws -> ControllerMotionSample {
    var data = Data(repeating: 0, count: 64)
    data[0] = 1
    for index in 0..<3 {
      write(gyro[index], into: &data, at: 16 + index * 2)
      write(accel[index], into: &data, at: 22 + index * 2)
    }
    return try #require(parser.parse(data: data).compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
  }

  private func factory() -> Data {
    var data = Data(repeating: 0, count: 41)
    data[0] = 5
    for (index, bias) in [Int16(20), -30, 40].enumerated() {
      write(bias, into: &data, at: 1 + index * 2)
      write(8000, into: &data, at: 7 + index * 4)
      write(-8000, into: &data, at: 9 + index * 4)
      write(8292, into: &data, at: 23 + index * 4)
      write(-8092, into: &data, at: 25 + index * 4)
    }
    write(500, into: &data, at: 19)
    write(500, into: &data, at: 21)
    return data
  }

  private func write(_ value: Int16, into data: inout Data, at offset: Int) {
    let raw = UInt16(bitPattern: value)
    data[offset] = UInt8(truncatingIfNeeded: raw)
    data[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
