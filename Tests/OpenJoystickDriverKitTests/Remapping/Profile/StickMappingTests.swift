import Foundation
import Testing
@testable import OpenJoystickDriverKit

struct StickMappingTests {
  @Test func defaultsAndAllModesRoundTrip() throws {
    let minimal = Data(#"{"source":"right"}"#.utf8)
    let decoded = try JSONDecoder().decode(RemappingStickMapping.self, from: minimal)
    #expect(decoded == RemappingStickMapping(source: .right))
    for mode in RemappingStickMode.allCases {
      let setting = RemappingStickMapping(source: .left, mode: mode)
      let data = try JSONEncoder().encode(setting)
      #expect(try JSONDecoder().decode(RemappingStickMapping.self, from: data) == setting)
    }
  }

  @Test func rejectsNonfiniteRatesAndInvertedHysteresis() {
    #expect(throws: RemappingStickMappingError.self) {
      try RemappingStickMapping(source: .left, aimDegreesPerSecond: .infinity).validate()
    }
    #expect(throws: RemappingStickMappingError.self) {
      try RemappingStickMapping(source: .left, flickThreshold: 0.1, flickHysteresis: 0.2).validate()
    }
    #expect(throws: RemappingStickTuningError.self) {
      try RemappingStickMapping(
        source: .left, tuning: RemappingStickTuning(responseExponent: -1)
      ).validate()
    }
  }
}
