import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingDirectionSourceTests {
  @Test func unboundTriggerDirectionActivatesAndReleasesLayer() throws {
    let profile = profile(layers: [RemappingLayer(
      name: "Trigger layer",
      activationMode: .hold,
      activator: .axisDirection(.leftTrigger, .positive),
      bindings: [RemappingBinding(
        source: .button(.south), destination: .keyboard(key: .a, modifiers: [])
      )]
    )])
    try profile.validate()
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.leftTriggerChanged(1), .buttonPressed(.a)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.a))])
    #expect(state.process(
      events: [.leftTriggerChanged(0)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyUp(.a))])
  }

  @Test func unboundStickDirectionParticipatesInChord() throws {
    let profile = profile(chords: [RemappingChord(
      sources: [.axisDirection(.leftStickX, .negative), .button(.south)],
      destination: .keyboard(key: .b, modifiers: [])
    )])
    try profile.validate()
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.leftStickChanged(x: -1, y: 0), .buttonPressed(.a)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.b))])
    #expect(state.process(
      events: [.leftStickChanged(x: 0, y: 0)], from: identifier, profile: profile, at: 1
    ) == [.system(.keyUp(.b))])
  }

  @Test func unboundDirectionParticipatesInSequence() throws {
    let profile = RemappingProfile(
      name: "Direction sequence",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      sequences: [RemappingSequence(
        sources: [.axisDirection(.rightStickX, .positive), .button(.south)],
        windowMs: 200,
        destination: .keyboard(key: .c, modifiers: [])
      )]
    )
    try profile.validate()
    var state = RemappingEngineState()
    #expect(state.process(
      events: [.rightStickChanged(x: 1, y: 0), .buttonPressed(.a)],
      from: identifier,
      profile: profile,
      at: 0
    ) == [.system(.keyDown(.c)), .system(.keyUp(.c))])
  }

  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)

  private func profile(chords: [RemappingChord] = [], layers: [RemappingLayer] = [])
    -> RemappingProfile
  {
    RemappingProfile(
      name: "Direction input",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [],
      chords: chords,
      layers: layers
    )
  }
}
