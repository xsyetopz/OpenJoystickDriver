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
  func theBindingValidatesAndDrivesMouseMovementThroughTheEngine() async throws {
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
  func aPointerStateChangeReachesTheEngineAsAPointerInput() {
    var moved = ControllerState()
    moved.pointer = StickPosition(x: 0.5, y: -0.25)
    let changes = RemappingEngineState.changes(from: ControllerState(), to: moved)
    #expect(changes == [.pointer(x: moved.pointer.x.normalized, y: moved.pointer.y.normalized)])
  }

  @Test(arguments: [RemappingAxis.pointerX, .pointerY])
  func theVirtualControllerHasNoPointerOutput(axis: RemappingAxis) {
    #expect(throws: RemappingValidationError.unsupportedGamepadAxis(axis)) {
      try profile(.leftStickX, to: .gamepadAxis(axis)).validate()
    }
  }
}
