import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct SteamMotionConversionTests {
  @Test
  func nominalScaleMapsGyroAndAccelIntoCanonicalFrame() throws {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[2] = 1
    report[3] = 60
    for (offset, value) in [
      (28, Int16(16384)), (30, Int16.min), (32, Int16(8192)), (34, Int16(16384)), (36, Int16.min),
      (38, Int16(8192)),
    ] {
      let raw = UInt16(bitPattern: value)
      report[offset] = UInt8(truncatingIfNeeded: raw)
      report[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
    }
    let parser = SteamControllerDriver()
    let events = try parser.parseReport(Data(report), at: 100)
    let sample = try #require(events?.motion.first)
    // Raw (16384, -32768, 8192) on both sensors: gyro (x, -y, z), accel (x, y, z).
    #expect(sample.calibrationSource == .nominalDeviceScale)
    #expect(isClose(sample.angularVelocity, radiansPerSecond(1000, 2000, 500)))
    #expect(isClose(sample.acceleration, metresPerSecondSquared(1, -2, 0.5)))
    #expect(sample.timestamp.basis == .hostEstimate)
    #expect(try parser.parseReport(Data(report), at: 200)?.motion.isEmpty == true)
  }
}
