import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingChordPriorityTests {
  @Test func largerChordReleasesSmallerOverlappingOutputBeforePress() {
    var state = RemappingEngineState()
    let profile = profile(chords: [
      chord([.south, .east], key: .a), chord([.south, .east, .north], key: .b)
    ])
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.a))])
    #expect(state.process(
      events: [.buttonPressed(.y)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyUp(.a)), .system(.keyDown(.b))])
    #expect(state.releaseController(identifier) == [.system(.keyUp(.b))])
  }

  @Test func equalSpecificityUsesProfileOrder() {
    var state = RemappingEngineState()
    let profile = profile(chords: [
      chord([.south, .east], key: .a), chord([.east, .north], key: .b)
    ])
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.y), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.a))])
  }

  @Test func disjointChordsCanRemainActiveTogether() {
    var state = RemappingEngineState()
    let profile = profile(chords: [
      chord([.south, .east], key: .a), chord([.west, .north], key: .b)
    ])
    #expect(state.process(
      events: [.buttonPressed(.a), .buttonPressed(.b), .buttonPressed(.x), .buttonPressed(.y)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.a)), .system(.keyDown(.b))])
  }

  @Test func latestLayerOverridesIdenticalChordSources() {
    var state = RemappingEngineState()
    let profile = profile(
      chords: [chord([.south, .east], key: .a)],
      layers: [RemappingLayer(
        name: "Alternate",
        activationMode: .hold,
        activator: .button(.leftShoulder),
        chords: [chord([.south, .east], key: .b)]
      )]
    )
    #expect(state.process(
      events: [.buttonPressed(.leftBumper), .buttonPressed(.a), .buttonPressed(.b)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.b))])
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func chord(_ buttons: Set<RemappingButton>, key: RemappingKeyboardKey)
    -> RemappingChord
  {
    RemappingChord(
      sources: Set(buttons.map(RemappingSource.button)),
      destination: .keyboard(key: key, modifiers: [])
    )
  }

  private func profile(chords: [RemappingChord], layers: [RemappingLayer] = [])
    -> RemappingProfile
  {
    RemappingProfile(
      name: "Chord priority",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: chords,
      layers: layers
    )
  }
}
