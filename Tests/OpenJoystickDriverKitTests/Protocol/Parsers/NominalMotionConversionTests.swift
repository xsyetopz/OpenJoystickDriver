import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NominalMotionConversionTests {
  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func nintendoConvertsEverySampleIntoTheStableHardwareFrame(_ layout: NintendoControllerLayout)
    throws
  {
    var bytes = [UInt8](repeating: 0, count: 49)
    bytes[0] = 0x30
    for sample in 0..<3 {
      let start = 13 + sample * 12
      for (index, value) in [Int16.min, 4096, 8192, 1000, 2000, 3000].enumerated() {
        write(value, into: &bytes, at: start + index * 2)
      }
    }
    let events = try SwitchProParser(layout: layout).parse(
      data: Data(bytes), receivedAtNanoseconds: 1
    )
    let samples = events.compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }
    #expect(samples.count == 3)
    #expect(samples.map { $0.timestamp.sequenceIndex } == [0, 1, 2])
    for sample in samples {
      #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 1000, y: 2000, z: 3000))
      #expect(sample.rawAccelerometer.x == .min)
      let reading = try #require(sample.physicalReading)
      #expect(reading.calibrationSource == .nominalDeviceScale)
      let expected = layout == .rightJoyCon ? [140.01, -210.02, -70.01] : [-140.01, 210.02, -70.01]
      #expect(abs(reading.gyroscopeDegreesPerSecond.x - expected[0]) < 0.01)
      #expect(abs(reading.gyroscopeDegreesPerSecond.y - expected[1]) < 0.01)
      #expect(abs(reading.gyroscopeDegreesPerSecond.z - expected[2]) < 0.01)
      #expect(reading.accelerationG == (layout == .rightJoyCon
        ? ControllerMotionVector(x: 1, y: -2, z: 8) : ControllerMotionVector(x: -1, y: 2, z: 8)))
    }
  }

  @Test func dualShockFourUsesSonyNominalUnitsWithoutChangingRawSamples() throws {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 1
    for (index, value) in [Int16(16), -16, 0, 8192, 0, -8192].enumerated() {
      write(value, into: &bytes, at: 13 + index * 2)
    }
    let events = try DS4Parser().parse(data: Data(bytes))
    let sample = try #require(events.compactMap { event -> ControllerMotionSample? in
      if case .motionSample(let sample) = event { return sample }
      return nil
    }.first)
    #expect(sample.rawGyroscope == ControllerRawSensorVector(x: 16, y: -16, z: 0))
    #expect(sample.physicalReading?.calibrationSource == .nominalDeviceScale)
    #expect(sample.physicalReading?.gyroscopeDegreesPerSecond
      == ControllerMotionVector(x: 1, y: -1, z: 0))
    #expect(sample.physicalReading?.accelerationG == ControllerMotionVector(x: 1, y: 0, z: -1))
  }

  private func write(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
    let raw = UInt16(bitPattern: value)
    bytes[offset] = UInt8(truncatingIfNeeded: raw)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
  }
}
