import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingPhysicalOutputTests {
  @Test
  func pressAndReleaseDeliverOneExactOwnedChannelClaim() async throws {
    let sink = RecordingPhysicalOutputSink()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), physicalOutputSink: sink)
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let bindingID = UUID()
    let output = RemappingPhysicalOutput.rumble(motor: .lowFrequency, intensity: 0.5)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(id: bindingID, source: .button(.south), destination: .physical(output))
      ]
    )

    try await engine.process(
      inputs: [.press(.south), .release(.south)],
      from: identifier,
      using: profile,
      at: 1
    )

    #expect(
      sink.events() == [
        .set(output, true, bindingID, identifier), .set(output, false, bindingID, identifier),
      ]
    )
  }

  @Test
  func drainReleasesActivePhysicalClaim() async throws {
    let sink = RecordingPhysicalOutputSink()
    let engine = RemappingEventEngine(sink: RemappingTestSink(), physicalOutputSink: sink)
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let output = RemappingPhysicalOutput.playerIndicator(.player1)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [RemappingBinding(source: .button(.south), destination: .physical(output))]
    )

    try await engine.process(inputs: [.press(.south)], from: identifier, using: profile, at: 1)
    try await engine.drain()

    #expect(sink.events().last == .set(output, false, profile.bindings[0].id, identifier))
  }

  @Test
  func rejectedPhysicalDeliveryFailsClosedForExactDevice() async {
    let sink = RecordingPhysicalOutputSink(rejectSets: true)
    let engine = RemappingEventEngine(sink: RemappingTestSink(), physicalOutputSink: sink)
    let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 3)
    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .physical(.brightness(0.5)))
      ]
    )

    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.process(
        inputs: [.press(.south)],
        from: identifier,
        using: profile,
        at: 1
      )
    }

    #expect(sink.events().last == .releaseAll(identifier))
  }
}
