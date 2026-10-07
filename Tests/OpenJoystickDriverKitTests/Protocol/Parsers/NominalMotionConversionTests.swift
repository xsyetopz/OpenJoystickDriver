import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NominalMotionConversionTests {
  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func nintendoConvertsEverySampleIntoTheStableHardwareFrame(
    _ layout: NintendoControllerLayout
  ) throws {
    var bytes = [UInt8](repeating: 0, count: 49)
    bytes[0] = 0x30
    for sample in 0..<3 {
      let start = 13 + sample * 12
      for (index, value) in [Int16.min, 4096, 8192, 1000, 2000, 3000].enumerated() {
        write(value, into: &bytes, at: start + index * 2)
      }
    }
    let events = try Switch1Driver(layout: layout).parseReport(Data(bytes), at: 1)
    let samples = (events?.motion ?? [])
    #expect(samples.count == 3)
    #expect(samples.map { $0.timestamp.sequenceIndex } == [0, 1, 2])
    for sample in samples {
      #expect(sample.calibrationSource == .nominalDeviceScale)
      // Raw gyro (1000, 2000, 3000) at 14.2842 counts per °/s; raw accel (-32768, 4096, 8192).
      let right = layout == .rightJoyCon
      let expected = radiansPerSecond(right ? 140.01 : -140.01, 70.01, right ? -210.02 : 210.02)
      #expect(isClose(sample.angularVelocity, expected, tolerance: 0.01 * .pi / 180))
      #expect(
        isClose(sample.acceleration, metresPerSecondSquared(right ? 1 : -1, -8, right ? -2 : 2))
      )
    }
  }

  @Test
  func dualShockFourUsesSonyNominalUnitsInTheCanonicalFrame() throws {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 1
    for (index, value) in [Int16(16), -16, 0, 8192, 0, -8192].enumerated() {
      write(value, into: &bytes, at: 13 + index * 2)
    }
    let events = try DualShock4Driver().parseReport(Data(bytes))
    let sample = try #require(events?.motion.first)
    #expect(sample.calibrationSource == .nominalDeviceScale)
    // Sensor (1, -1, 0) °/s and (1, 0, -1) g land canonical as (x, -z, y).
    #expect(isClose(sample.angularVelocity, radiansPerSecond(1, 0, -1)))
    #expect(isClose(sample.acceleration, metresPerSecondSquared(1, 1, 0)))
  }

  private func write(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
    let raw = UInt16(bitPattern: value)
    bytes[offset] = UInt8(truncatingIfNeeded: raw)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
