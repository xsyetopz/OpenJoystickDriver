import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionTuningTests {
  @Test func omittedSettingsDecodeToDefaultsAndCustomValuesRoundTrip() throws {
    #expect(try JSONDecoder().decode(RemappingMotionTuning.self, from: Data("{}".utf8)) == .default)
    let tuning = RemappingMotionTuning(
      space: .world,
      pitchSensitivity: 2,
      invertYaw: true,
      smoothingHalfTimeMs: 50,
      automaticBias: false
    )
    let data = try JSONEncoder().encode(tuning)
    #expect(try JSONDecoder().decode(RemappingMotionTuning.self, from: data) == tuning)
  }

  @Test(arguments: [
    #"{"yaw_sensitivity":-1}"#,
    #"{"smoothing_half_time_ms":1001}"#,
    #"{"side_reduction_threshold":2}"#,
    #"{"space":"unknown"}"#
  ]) func invalidDecodedTuningIsRejected(_ json: String) {
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(RemappingMotionTuning.self, from: Data(json.utf8))
    }
  }

  @Test func programmaticNonFiniteTuningIsRejected() {
    #expect(throws: RemappingMotionTuningError.self) {
      try RemappingMotionTuning(pitchSensitivity: .nan).validate()
    }
  }
}
