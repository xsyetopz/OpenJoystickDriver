import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingActivationTests {
  @Test func longHoldFiresAlternateDestinationAfterThreshold() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        longHold: RemappingLongHold(durationMs: 500, destination: .keyboard(key: .b, modifiers: []))
      ),
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    #expect(sink.actions().isEmpty)

    try await engine.tick(at: start + 400_000_000)
    #expect(sink.actions().isEmpty)

    try await engine.tick(at: start + 500_000_000)
    #expect(sink.actions() == [.keyDown(.b)])

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 800_000_000
    )
    #expect(sink.actions() == [.keyDown(.b), .keyUp(.b)])
  }

  @Test func longHoldEarlyReleaseFiresDefaultAsQuickDownUp() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        longHold: RemappingLongHold(durationMs: 500, destination: .keyboard(key: .b, modifiers: []))
      ),
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    #expect(sink.actions().isEmpty)

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 200_000_000
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
  }

  @Test func doubleTapFiresAlternateOnSecondPress() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        doubleTap: RemappingDoubleTap(windowMs: 300, destination: .keyboard(key: .c, modifiers: []))
      ),
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    #expect(sink.actions().isEmpty)

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 100_000_000
    )
    #expect(sink.actions().isEmpty)

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 200_000_000
    )
    #expect(sink.actions() == [.keyDown(.c)])

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 300_000_000
    )
    #expect(sink.actions() == [.keyDown(.c), .keyUp(.c)])
  }

  @Test func doubleTapWindowExpiryFiresDefault() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        doubleTap: RemappingDoubleTap(windowMs: 300, destination: .keyboard(key: .c, modifiers: []))
      ),
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 100_000_000
    )
    #expect(sink.actions().isEmpty)

    try await engine.tick(at: start + 100_000_000 + 300_000_000)
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
  }

  @Test func bindingWithoutActivationFiresImmediately() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [binding(source: .button(.south), key: .space)])

    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: 0
    )

    #expect(sink.actions() == [.keyDown(.space), .keyUp(.space)])
  }

  @Test func longHoldDoesNotFireAfterEarlyReleaseWhenBothConfigured() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: []),
        longHold: RemappingLongHold(
          durationMs: 500,
          destination: .keyboard(key: .b, modifiers: [])
        ),
        doubleTap: RemappingDoubleTap(windowMs: 300, destination: .keyboard(key: .c, modifiers: []))
      ),
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    #expect(sink.actions().isEmpty)

    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 200_000_000
    )
    #expect(sink.actions().isEmpty)

    try await engine.tick(at: start + 600_000_000)
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
  }

  // MARK: - Helpers

  private func profile(name: String = "Activation", bindings: [RemappingBinding])
    -> RemappingProfile
  {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private func binding(
    source: RemappingSource,
    key: RemappingKeyboardKey,
    modifiers: Set<RemappingKeyModifier> = []
  ) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: modifiers))
  }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }
}
