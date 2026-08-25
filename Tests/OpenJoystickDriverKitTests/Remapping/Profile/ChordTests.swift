import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingChordTests {
  @Test func chordFiresWhenAllSourcesAreActive() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(
      bindings: [
        binding(source: .button(.south), key: .a), binding(source: .button(.east), key: .b)
      ],
      chords: [
        RemappingChord(
          sources: [.button(.south), .button(.east)],
          destination: .keyboard(key: .c, modifiers: [])
        )
      ]
    )

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    #expect(sink.actions() == [.keyDown(.a)])

    try await engine.process(
      events: [.buttonPressed(.b)],
      from: device(1),
      using: currentProfile,
      at: 1
    )
    #expect(sink.actions() == [.keyDown(.a), .keyDown(.c)])

    try await engine.process(
      events: [.buttonReleased(.b)],
      from: device(1),
      using: currentProfile,
      at: 2
    )
    #expect(sink.actions() == [.keyDown(.a), .keyDown(.c), .keyUp(.c)])

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 3
    )
    #expect(sink.actions() == [.keyDown(.a), .keyDown(.c), .keyUp(.c), .keyUp(.a)])
  }

  // MARK: - Helpers

  private func profile(
    name: String = "Chord",
    bindings: [RemappingBinding],
    chords: [RemappingChord] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings,
      chords: chords
    )
  }

  private func binding(source: RemappingSource, key: RemappingKeyboardKey) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: []))
  }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }
}
