import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DualSenseCalibrationTests {
  private let request = PhysicalHIDFeatureReadRequest(reportID: 5, length: 41)

  @Test
  func revisionChangesOnlyForNewAcceptedCoefficients() throws {
    let parser = DualSenseDriver()
    var data = factory()
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 1)
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 1)
    write(21, into: &data, at: 1)
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationRevision == 2)
  }

  @Test
  func factorySampleRoundTripsWithRevision() throws {
    let parser = DualSenseDriver()
    #expect(parser.consumeFeatureReply(factory(), request: request))
    let sample = try motion(parser)
    let encoded = try JSONEncoder().encode(sample)
    #expect(try JSONDecoder().decode(ControllerMotionSample.self, from: encoded) == sample)
    #expect(sample.calibrationRevision == 1)
  }

  @Test
  func nominalUnitsMapSensorAxesToCanonicalSI() throws {
    let sample = try motion(DualSenseDriver(), gyro: [16, -16, 0], accel: [8192, 0, -8192])
    // Sensor (1, -1, 0) °/s and (1, 0, -1) g land canonical as (x, -z, y).
    #expect(sample.calibrationSource == .nominalDeviceScale)
    #expect(isClose(sample.angularVelocity, radiansPerSecond(1, 0, -1)))
    #expect(isClose(sample.acceleration, metresPerSecondSquared(1, 1, 0)))
  }

  @Test
  func acceptedFactoryReportAppliesBiasAndScaleAtomically() throws {
    let parser = DualSenseDriver()
    #expect(parser.consumeFeatureReply(factory(), request: request))
    let zero = try motion(parser, gyro: [20, -30, 40], accel: [100, 100, 100])
    #expect(zero.calibrationSource == .deviceFactory)
    #expect(isClose(zero.angularVelocity, ControllerMotionVector(x: 0, y: 0, z: 0)))
    #expect(isClose(zero.acceleration, ControllerMotionVector(x: 0, y: 0, z: 0)))
    let endpoint = try motion(parser, gyro: [36, -14, 56], accel: [8292, -8092, 100])
    #expect(isClose(endpoint.angularVelocity, radiansPerSecond(1, -1, 1)))
    #expect(isClose(endpoint.acceleration, metresPerSecondSquared(1, 0, -1)))
    var invalid = factory()
    invalid[24] = 0
    #expect(!parser.consumeFeatureReply(invalid, request: request))
    let retained = try motion(parser, gyro: [20, -30, 40], accel: [100, 100, 100])
    #expect(retained.angularVelocity == zero.angularVelocity)
    #expect(retained.acceleration == zero.acceleration)
    #expect(retained.calibrationRevision == zero.calibrationRevision)
  }

  @Test
  func bluetoothCalibrationRequiresFeatureCRC() throws {
    let parser = DualSenseDriver(prefersBluetooth: true)
    #expect(!parser.consumeFeatureReply(factory(), request: request))
    var data = factory()
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in [UInt8(0xA3)] + Array(data.prefix(37)) {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
    }
    crc = ~crc
    for index in 0..<4 { data[37 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    #expect(parser.consumeFeatureReply(data, request: request))
    #expect(try motion(parser).calibrationSource == .deviceFactory)
  }

  @Test
  func stoppedPipelineRejectsCalibrationReplies() async {
    let parser = DualSenseDriver()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x054C, productID: 0x0CE6),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: parser,
      dispatcher: LoggingOutputDispatcher()
    )
    #expect(await pipeline.consumeFeatureReply(factory(), request: request) == false)
    await pipeline.start()
    #expect(await pipeline.consumeFeatureReply(factory(), request: request))
    await pipeline.stop()
    #expect(await pipeline.consumeFeatureReply(factory(), request: request) == false)
  }

  private func motion(
    _ parser: DualSenseDriver,
    gyro: [Int16] = [0, 0, 0],
    accel: [Int16] = [0, 0, 0]
  ) throws -> ControllerMotionSample {
    var data = Data(repeating: 0, count: 64)
    data[0] = 1
    for index in 0..<3 {
      write(gyro[index], into: &data, at: 16 + index * 2)
      write(accel[index], into: &data, at: 22 + index * 2)
    }
    return try #require(parser.parseReport(data)?.motion.first)
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
