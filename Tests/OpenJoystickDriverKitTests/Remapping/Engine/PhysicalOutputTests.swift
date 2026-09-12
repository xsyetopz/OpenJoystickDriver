import Foundation
import Testing

@testable import OpenJoystickDriverKit

private final class RecordingPhysicalOutputSink: RemappingPhysicalOutputSink, @unchecked Sendable {
  enum Event: Equatable {
    case set(RemappingPhysicalOutput, Bool, UUID, DeviceIdentifier)
    case releaseAll(DeviceIdentifier)
  }

  private let lock = NSLock()
  private var recorded: [Event] = []
  private let rejectSets: Bool

  init(rejectSets: Bool = false) { self.rejectSets = rejectSets }

  func set(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) throws {
    lock.withLock { recorded.append(.set(output, active, owner, identifier)) }
    if rejectSets { throw RemappingEventEngineError.sinkUnavailable }
  }

  func releaseAll(for identifier: DeviceIdentifier) throws {
    lock.withLock { recorded.append(.releaseAll(identifier)) }
  }

  func events() -> [Event] { lock.withLock { recorded } }
}

struct RemappingPhysicalOutputTests {
  @Test func pressAndReleaseDeliverOneExactOwnedChannelClaim() async throws {
    let sink = RecordingPhysicalOutputSink()
    let engine = RemappingEventEngine(
      sink: RemappingTestSink(),
      physicalOutputSink: sink
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let bindingID = UUID()
    let output = RemappingPhysicalOutput.rumble(motor: .leftMain, intensity: 0.5)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          id: bindingID,
          source: .button(.south),
          destination: .physical(output)
        )
      ]
    )

    try await engine.process(
      events: [.buttonPressed(.a), .buttonReleased(.a)],
      from: identifier,
      using: profile,
      at: 1
    )

    #expect(
      sink.events() == [
        .set(output, true, bindingID, identifier),
        .set(output, false, bindingID, identifier),
      ]
    )
  }

  @Test func drainReleasesAnActivePhysicalClaim() async throws {
    let sink = RecordingPhysicalOutputSink()
    let engine = RemappingEventEngine(
      sink: RemappingTestSink(),
      physicalOutputSink: sink
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let output = RemappingPhysicalOutput.playerIndicator(.player1)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .physical(output))
      ]
    )

    try await engine.process(events: [.buttonPressed(.a)], from: identifier, using: profile, at: 1)
    try await engine.drain()

    #expect(sink.events().last == .set(output, false, profile.bindings[0].id, identifier))
  }

  @Test func rejectedPhysicalDeliveryFailsClosedForTheExactDevice() async {
    let sink = RecordingPhysicalOutputSink(rejectSets: true)
    let engine = RemappingEventEngine(
      sink: RemappingTestSink(),
      physicalOutputSink: sink
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .physical(.brightness(0.5))
        )
      ]
    )

    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        events: [.buttonPressed(.a)], from: identifier, using: profile, at: 1
      )
    }

    #expect(sink.events().last == .releaseAll(identifier))
  }
}
