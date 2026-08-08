import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingSequenceTests {
  @Test func sequenceFiresWhenSourcesPressedInOrderWithinWindow() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(
      bindings: [],
      sequences: [
        RemappingSequence(
          sources: [.dpad(.up), .dpad(.up), .dpad(.down), .dpad(.down)],
          windowMs: 1000,
          destination: .keyboard(key: .space, modifiers: [])
        ),
      ]
    )
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.dpadChanged(.north)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    try await engine.process(
      events: [.dpadChanged(.neutral)],
      from: device(1),
      using: currentProfile,
      at: start + 100_000_000
    )
    try await engine.process(
      events: [.dpadChanged(.north)],
      from: device(1),
      using: currentProfile,
      at: start + 200_000_000
    )
    try await engine.process(
      events: [.dpadChanged(.neutral)],
      from: device(1),
      using: currentProfile,
      at: start + 300_000_000
    )
    try await engine.process(
      events: [.dpadChanged(.south)],
      from: device(1),
      using: currentProfile,
      at: start + 400_000_000
    )
    try await engine.process(
      events: [.dpadChanged(.neutral)],
      from: device(1),
      using: currentProfile,
      at: start + 500_000_000
    )
    try await engine.process(
      events: [.dpadChanged(.south)],
      from: device(1),
      using: currentProfile,
      at: start + 600_000_000
    )

    #expect(sink.actions() == [.keyDown(.space), .keyUp(.space)])
  }

  // MARK: - Helpers

  private func profile(
    name: String = "Sequence",
    bindings: [RemappingBinding],
    sequences: [RemappingSequence] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings,
      sequences: sequences
    )
  }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }
}
