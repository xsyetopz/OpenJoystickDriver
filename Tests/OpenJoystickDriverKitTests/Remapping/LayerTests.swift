import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingLayerTests {
  @Test func holdLayerOverridesBaseBindingWhileActivatorHeld() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let layer = RemappingLayer(
      name: "Combat",
      activationMode: .hold,
      activator: .button(.leftShoulder),
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .b, modifiers: []))
      ]
    )
    let currentProfile = profile(
      bindings: [binding(source: .button(.south), key: .a)],
      layers: [layer]
    )

    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])

    _ = sink.removeActions()

    try await engine.process(
      events: [.buttonPressed(.leftBumper)],
      from: device(1),
      using: currentProfile,
      at: 1
    )
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: 2
    )
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 3
    )
    #expect(sink.actions() == [.keyDown(.b), .keyUp(.b)])

    _ = sink.removeActions()

    try await engine.process(
      events: [.buttonReleased(.leftBumper)],
      from: device(1),
      using: currentProfile,
      at: 4
    )
    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 5
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
  }

  @Test func toggleLayerActivatesOnPressAndDeactivatesOnNextPress() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let layer = RemappingLayer(
      name: "Nav",
      activationMode: .toggle,
      activator: .button(.rightShoulder),
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .c, modifiers: []))
      ]
    )
    let currentProfile = profile(
      bindings: [binding(source: .button(.south), key: .a)],
      layers: [layer]
    )

    try await engine.process(
      events: [.buttonPressed(.rightBumper), .buttonReleased(.rightBumper)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    _ = sink.removeActions()

    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 1
    )
    #expect(sink.actions() == [.keyDown(.c), .keyUp(.c)])

    _ = sink.removeActions()

    try await engine.process(
      events: [.buttonPressed(.rightBumper), .buttonReleased(.rightBumper)],
      from: device(1),
      using: currentProfile,
      at: 2
    )
    _ = sink.removeActions()

    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 3
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
  }

  // MARK: - Helpers

  private func profile(
    name: String = "Layer",
    bindings: [RemappingBinding],
    layers: [RemappingLayer] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings,
      layers: layers
    )
  }

  private func binding(source: RemappingSource, key: RemappingKeyboardKey) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: []))
  }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }
}
