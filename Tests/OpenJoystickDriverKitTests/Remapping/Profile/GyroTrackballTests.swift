import Foundation
import Testing
@testable import OpenJoystickDriverKit

struct GyroTrackballTests {
  @Test func defaultsAndRoundTrip() throws {
    let source = RemappingSource.button(.south)
    let trackball = RemappingGyroTrackball(source: source, axes: .yaw, consumesSource: false)
    let output = RemappingGyroOutput(mode: .mouse, trackball: trackball)
    let encoded = try JSONEncoder().encode(output)
    #expect(try JSONDecoder().decode(RemappingGyroOutput.self, from: encoded) == output)
    let legacy = Data(#"{"mode":"mouse"}"#.utf8)
    #expect(try JSONDecoder().decode(RemappingGyroOutput.self, from: legacy).trackball == nil)
    let partial = Data(#"{"source":{"type":"button","button":"south"}}"#.utf8)
    let decoded = try JSONDecoder().decode(RemappingGyroTrackball.self, from: partial)
    #expect(decoded.axes == .both)
    #expect(decoded.decayHalvingsPerSecond == 1)
    #expect(decoded.consumesSource)
  }

  @Test func rejectsContinuousSourceAndInvalidDecay() {
    #expect(throws: RemappingGyroOutputError.self) {
      try RemappingGyroTrackball(source: .axis(.leftStickX)).validate()
    }
    for decay in [-1, Double.nan, Double.infinity, 1001] {
      #expect(throws: RemappingGyroOutputError.self) {
        try RemappingGyroOutput(trackball: RemappingGyroTrackball(
          source: .button(.south), decayHalvingsPerSecond: decay
        )).validate()
      }
    }
  }
}
