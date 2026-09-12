import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SteamMotionConversionTests {
  @Test func physicalUnitsPreserveRawAxesAndUseDistinctSensorTransforms() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[2] = 1
    report[3] = 60
    for (offset, value) in [
      (28, Int16(16384)), (30, Int16.min), (32, Int16(8192)),
      (34, Int16(16384)), (36, Int16.min), (38, Int16(8192))
    ] {
      let raw = UInt16(bitPattern: value)
      report[offset] = UInt8(truncatingIfNeeded: raw)
      report[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
    }
    let parser = SteamControllerParser()
    let events = try parser.parse(data: Data(report), receivedAtNanoseconds: 100)
    let sample = try #require(events.compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
    #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 16384, y: .min, z: 8192))
    #expect(sample.rawAccelerometer == sample.rawGyroscope)
    let reading = try #require(sample.physicalReading)
    #expect(reading.calibrationSource == .nominalDeviceScale)
    #expect(reading.gyroscopeDegreesPerSecond == ControllerMotionVector(x: 1000, y: 500, z: -2000))
    #expect(reading.accelerationG == ControllerMotionVector(x: 1, y: 0.5, z: 2))
    #expect(sample.timestamp.basis == .hostEstimate)
    #expect(try parser.parse(data: Data(report), receivedAtNanoseconds: 200).isEmpty)
  }
}
