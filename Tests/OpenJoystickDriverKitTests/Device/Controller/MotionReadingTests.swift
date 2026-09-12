import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionReadingTests {
  @Test func rejectsNonfinitePhysicalVectors() {
    #expect(ControllerMotionReading(
      gyroscopeDegreesPerSecond: ControllerMotionVector(x: .nan, y: 0, z: 0),
      accelerationG: ControllerMotionVector(x: 0, y: 1, z: 0),
      calibrationSource: .nominalDeviceScale
    ) == nil)
  }

  @Test func olderRawSamplePayloadRemainsReadable() throws {
    let sample = ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 3,
        elapsedNanoseconds: 0,
        tickNanosecondsNumerator: 1000,
        tickNanosecondsDenominator: 3,
        sequenceIndex: 0
      ),
      rawGyroscope: ControllerRawSensorVector(x: 1, y: 2, z: 3),
      rawAccelerometer: ControllerRawSensorVector(x: 4, y: 5, z: 6)
    )
    let data = try JSONEncoder().encode(sample)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["physicalReading"] == nil)
    #expect(try JSONDecoder().decode(ControllerMotionSample.self, from: data) == sample)
  }

  @Test func decodingCannotBypassFiniteValidation() throws {
    let data = Data(#"""
      {
        "gyroscopeDegreesPerSecond": {"x":"inf","y":0,"z":0},
        "accelerationG": {"x":0,"y":1,"z":0},
        "calibrationSource": "nominalDeviceScale"
      }
      """#.utf8)
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
    )
    #expect(throws: DecodingError.self) {
      try decoder.decode(ControllerMotionReading.self, from: data)
    }
  }
}
