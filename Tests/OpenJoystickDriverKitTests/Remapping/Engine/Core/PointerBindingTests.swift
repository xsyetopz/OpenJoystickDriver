import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingPointerBindingTests {
  private let device = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  private func profile(
    _ source: RemappingAxis,
    to destination: RemappingDestination
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .axis(source),
          destination: destination,
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )
      ]
    )
  }

  @Test
  func bindingValidatesAndDrivesMouseMovementThroughEngine() async throws {
    let current = profile(.pointerX, to: .mouseMovement(.x))
    try current.validate()
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)

    try await engine.process(inputs: [.pointer(x: 0.5, y: 0)], from: device, using: current, at: 0)
    try await engine.tick(at: 1)
    try await engine.process(inputs: [.pointer(x: 0, y: 0)], from: device, using: current, at: 2)
    try await engine.tick(at: 3)

    let moves = sink.actions().compactMap { action -> Double? in
      if case .mouseMoved(.x, let amount) = action { amount } else { nil }
    }
    #expect(moves.first.map { $0 > 0 } == true)
    #expect(moves.last == 0)
  }

  @Test
  func positionBindingValidatesAndPlacesCursorOnEachAxisChange() async throws {
    let current = profile(.pointerX, to: .pointerPosition(.x))
    try current.validate()
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)

    try await engine.process(inputs: [.pointer(x: 0.5, y: 0)], from: device, using: current, at: 0)
    try await engine.tick(at: 1)
    try await engine.tick(at: 2)

    #expect(sink.actions() == [.pointerPlaced(axis: .x, position: quantizedStick(0.5))])
  }

  @Test
  func positionDestinationNeedsAxisSourceAndRoundTrips() throws {
    let button = RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: .pointerPosition(.x))]
    )
    #expect(throws: (any Error).self) { try button.validate() }
    let data = try JSONEncoder().encode(RemappingDestination.pointerPosition(.y))
    #expect(String(bytes: data, encoding: .utf8)?.contains("\"PointerPosition\"") == true)
    #expect(try JSONDecoder().decode(RemappingDestination.self, from: data) == .pointerPosition(.y))
  }

  @Test
  func pointerStateChangeReachesEngineAsPointerInput() {
    var moved = ControllerState()
    moved.pointer = StickPosition(x: 0.5, y: -0.25)
    let changes = RemappingEngineState.changes(from: ControllerState(), to: moved)
    #expect(changes == [.pointer(x: moved.pointer.x.normalized, y: moved.pointer.y.normalized)])
  }

  @Test(arguments: [RemappingAxis.pointerX, .pointerY])
  func virtualControllerHasNoPointerOutput(axis: RemappingAxis) {
    #expect(throws: RemappingValidationError.unsupportedGamepadAxis(axis)) {
      try profile(.leftStickX, to: .gamepadAxis(axis)).validate()
    }
  }

  private func profile(
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    layers: [RemappingLayer] = [],
    gyroOutput: RemappingGyroOutput = RemappingGyroOutput()
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      gyroOutput: gyroOutput,
      bindings: [],
      chords: chords,
      sequences: sequences,
      layers: layers
    )
  }

  @Test
  func profileBindsPointerOnlyThroughPointerSource() {
    #expect(profile(.pointerY, to: .mouseMovement(.y)).bindsPointer)
    #expect(!profile(.leftStickX, to: .mouseMovement(.x)).bindsPointer)
    #expect(!profile().bindsPointer)
  }

  @Test
  func everyPlaceSourceCanAppearCountsAsBinding() {
    let right = RemappingSource.axisDirection(.pointerX, .positive)
    let other = RemappingSource.button(.south)
    let destination = RemappingDestination.mouseButton(.left)
    #expect(
      profile(chords: [RemappingChord(sources: [other, right], destination: destination)])
        .bindsPointer
    )
    #expect(
      profile(sequences: [
        RemappingSequence(sources: [other, right], windowMs: 300, destination: destination)
      ]).bindsPointer
    )
    let layer = { (activator: RemappingSource, bindings: [RemappingBinding]) in
      RemappingLayer(
        name: "Aim",
        activationMode: .hold,
        activator: activator,
        bindings: bindings
      )
    }
    #expect(profile(layers: [layer(right, [])]).bindsPointer)
    #expect(
      profile(layers: [layer(other, [RemappingBinding(source: right, destination: destination)])])
        .bindsPointer
    )
    #expect(
      profile(layers: [
        RemappingLayer(
          name: "Aim",
          activationMode: .hold,
          activator: other,
          chords: [RemappingChord(sources: [other, right], destination: destination)]
        )
      ]).bindsPointer
    )
    #expect(
      profile(
        gyroOutput: RemappingGyroOutput(
          mode: .mouse,
          activationMode: .whileHeld,
          activationSource: right
        )
      ).bindsPointer
    )
    #expect(
      profile(
        gyroOutput: RemappingGyroOutput(
          mode: .mouse,
          trackball: RemappingGyroTrackball(source: right)
        )
      ).bindsPointer
    )
    #expect(!profile(layers: [layer(other, [])]).bindsPointer)
  }
}
