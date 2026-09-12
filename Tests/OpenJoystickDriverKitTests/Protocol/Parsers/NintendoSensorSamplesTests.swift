import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NintendoSensorSamplesTests {
  private func report() -> Data {
    var bytes = [UInt8](repeating: 0, count: 49)
    bytes[0] = 0x30
    bytes[1] = 255
    bytes[7] = 8
    bytes[8] = 128
    bytes[10] = 8
    bytes[11] = 128
    for index in 0..<3 {
      let offset = 13 + 12 * index
      bytes[offset] = UInt8(index + 1)
      bytes[offset + 7] = 0x80
      bytes[offset + 8] = 0xFF
      bytes[offset + 9] = 0x7F
      bytes[offset + 10] = 0xFF
      bytes[offset + 11] = 0xFF
    }
    return Data(bytes)
  }

  private func samples(_ events: [ControllerEvent]) -> [ControllerMotionSample] {
    events.compactMap {
      if case .motionSample(let sample) = $0 { return sample }
      return nil
    }
  }

  @Test func threeRawSamplesRetainOrderAndUseExplicitHostEstimates() throws {
    let parser: any InputParser = SwitchProParser()
    let first = samples(try parser.parse(data: report(), receivedAtNanoseconds: 100_000_000))
    #expect(first.map(\.rawAccelerometer.x) == [1, 2, 3])
    #expect(first.allSatisfy {
      $0.rawGyroscope == ControllerRawSensorVector(x: -32_768, y: 32_767, z: -1)
    })
    #expect(first.map(\.timestamp.elapsedNanoseconds) == [0, 5_000_000, 10_000_000])
    #expect(first.map(\.timestamp.sequenceIndex) == [0, 1, 2])
    #expect(first.allSatisfy {
      $0.timestamp.basis == .hostEstimate && $0.timestamp.rawCounter == 255
        && $0.timestamp.tickNanosecondsNumerator == nil
        && $0.timestamp.tickNanosecondsDenominator == nil
    })
    let second = samples(try parser.parse(data: report(), receivedAtNanoseconds: 115_000_000))
    #expect(second.map(\.timestamp.elapsedNanoseconds) == [15_000_000, 20_000_000, 25_000_000])
    #expect(second.map(\.timestamp.sequenceIndex) == [3, 4, 5])
  }

  @Test func backwardReceiptDoesNotReverseTimeAndLongGapDoesNotStretchSamples() throws {
    let parser = SwitchProParser()
    _ = try parser.parse(data: report(), receivedAtNanoseconds: 100_000_000)
    let backward = samples(try parser.parse(data: report(), receivedAtNanoseconds: 90_000_000))
    #expect(backward.map(\.timestamp.elapsedNanoseconds) == [10_000_000, 10_000_000, 10_000_000])
    let gap = samples(try parser.parse(data: report(), receivedAtNanoseconds: 1_100_000_000))
    #expect(
      gap.map(\.timestamp.elapsedNanoseconds) == [1_000_000_000, 1_005_000_000, 1_010_000_000]
    )
  }

  @Test func shortReportCannotAdvanceSensorClock() throws {
    let parser = SwitchProParser()
    let short = try parser.parse(data: report().prefix(12), receivedAtNanoseconds: 1)
    #expect(samples(short).isEmpty)
    let full = samples(try parser.parse(data: report(), receivedAtNanoseconds: 100_000_000))
    #expect(full.first?.timestamp.elapsedNanoseconds == 0)
    #expect(full.first?.timestamp.sequenceIndex == 0)
    #expect(parser.physicalInputCapabilities.rawMotion)
    #expect(parser.physicalInputCapabilities.touchContactsPerFrame == 0)
  }
}
