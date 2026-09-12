import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingChordTimingTests {
  @Test(arguments: [UInt64(49_999_999), 50_000_000, 50_000_001])
  func simultaneousWindowIncludesExactBoundary(delay: UInt64) {
    var state = RemappingEngineState()
    let profile = profile(mode: .simultaneous)
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0
    ).isEmpty)
    let actions = state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: delay
    )
    #expect(actions == (delay <= 50_000_000 ? [.system(.keyDown(.c))] : []))
  }

  @Test func modifierDoesNotRequireSimultaneousPresses() {
    var state = RemappingEngineState()
    let profile = profile(mode: .modifier)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    #expect(state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: 5_000_000_000
    ) == [.system(.keyDown(.c))])
  }

  @Test func releaseAndRepressUsesFreshPressTime() {
    var state = RemappingEngineState()
    let profile = profile(mode: .simultaneous)
    _ = state.process(events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 0)
    _ = state.process(
      events: [.buttonPressed(.b)], from: identifier, profile: profile, at: 100_000_000
    )
    _ = state.process(
      events: [.buttonReleased(.a)], from: identifier, profile: profile, at: 110_000_000
    )
    #expect(state.process(
      events: [.buttonPressed(.a)], from: identifier, profile: profile, at: 120_000_000
    ) == [.system(.keyDown(.c))])
    #expect(state.process(
      events: [.buttonReleased(.b)], from: identifier, profile: profile, at: 130_000_000
    ) == [.system(.keyUp(.c))])
  }

  @Test func legacyChordDecodesWithoutTimingFields() throws {
    let chord = try #require(profile(mode: .modifier).chords.first)
    let data = try JSONEncoder().encode(chord)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["mode"] == nil)
    #expect(object["window_ms"] == nil)
    let decoded = try JSONDecoder().decode(RemappingChord.self, from: data)
    #expect(decoded.mode == .modifier)
    #expect(decoded.windowMs == 50)
  }

  @Test(arguments: [Double.nan, .infinity, 0, 1_001])
  func rejectsInvalidChordWindow(window: Double) {
    let invalid = RemappingProfile(
      name: "Invalid timing",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: [RemappingChord(
        sources: [.button(.south), .button(.east)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: .simultaneous,
        windowMs: window
      )]
    )
    #expect(throws: RemappingValidationError.chordWindowOutOfRange(index: 0)) {
      try invalid.validate()
    }
  }

  @Test func chordModeSurvivesPersistence() throws {
    let original = profile(mode: .simultaneous)
    try original.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(original)
    )
    #expect(decoded == original)
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(mode: RemappingChordMode) -> RemappingProfile {
    RemappingProfile(
      name: "Timed chord",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: [RemappingChord(
        sources: [.button(.south), .button(.east)],
        destination: .keyboard(key: .c, modifiers: []),
        mode: mode
      )]
    )
  }
}
