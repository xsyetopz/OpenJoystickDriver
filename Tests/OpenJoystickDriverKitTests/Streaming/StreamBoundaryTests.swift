import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The source and sink boundary: what each shape of frame reaches, and what a sink refuses.
struct StreamBoundaryTests {
  private static let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  private final class RecordingDispatcher: OutputDispatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var published: [ControllerEvent] = []
    private var activated: [LogicalControllerID] = []
    var suppressOutput = false

    func dispatch(
      _ event: ControllerEvent,
      from _: LogicalControllerID
    ) async {  // swiftlint:disable:this async_without_await
      lock.withLock { published.append(event) }
    }

    func activateOutput(for identifier: LogicalControllerID) {
      lock.withLock { activated.append(identifier) }
    }

    func activations() -> [LogicalControllerID] { lock.withLock { activated } }

    func events() -> [ControllerEvent] { lock.withLock { published } }
  }

  private final class BareSink: OutputSink, Sendable {
    let destination = OutputDestination.physicalOutput
  }

  @Test
  func sinkRefusesWhatItDoesNotConsume() async {
    let sink = BareSink()
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await sink.consume(.gamepad(RemappingGamepadState(), for: Self.identifier)) {}
    }
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await sink.consume(.stopRumble, for: Self.identifier)
    }
  }

  @Test
  func dispatcherConsumesControllerFrames() async throws {
    let dispatcher = RecordingDispatcher()
    let delivered = Locked(0)
    let event = ControllerEvent([.leftStick(x: 0.5, y: 0)])

    try await dispatcher.consume(
      .controller(event, from: Self.identifier)
    ) { delivered.withLock { $0 += 1 } }

    #expect(dispatcher.destination == .virtualDevice)
    #expect(dispatcher.events().count == 1)
    // The default `dispatchPublishing` never reports a publication, so no delivery is stamped.
    #expect(delivered.withLock { $0 } == 0)
  }

  @Test
  func dispatcherWithoutGamepadSinkRefusesGamepadFrames() async {
    let dispatcher = RecordingDispatcher()
    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await dispatcher.consume(.gamepad(RemappingGamepadState(), for: Self.identifier)) {}
    }
  }

  @Test
  func dispatcherConsumesActivationFrameAndReportsItDelivered() async throws {
    let dispatcher = RecordingDispatcher()
    let delivered = Locked(0)

    try await dispatcher.consume(.activation(Self.identifier)) { delivered.withLock { $0 += 1 } }

    #expect(dispatcher.activations() == [Self.identifier])
    #expect(delivered.withLock { $0 } == 1)
  }

  @Test
  func dispatcherRefusesFeedFrame() async {
    let dispatcher = RecordingDispatcher()
    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await dispatcher.consume(.feed(VirtualFeedFrame(buttons: [], axes: [:]))) {}
    }
    #expect(dispatcher.activations().isEmpty)
  }

  @Test
  func sinkRefusesMappingOutputClaimUnlessItAppliesOne() async {
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await BareSink().consume(
        MappingOutputClaim(.brightness(0.5), active: true, owner: UUID()),
        for: Self.identifier
      )
    }
  }

  @Test
  func sinkRefusesMappingReleaseAndProfileColorUnlessItAppliesThem() async {
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await BareSink().consume(MappingOutputRelease(), for: Self.identifier)
    }
    await #expect(throws: StreamBoundaryError.unsupported(.physicalOutput)) {
      try await BareSink().consume(ProfileColorClaim(nil), for: Self.identifier)
    }
  }

  @Test
  func pipelineIsPhysicalControllerSourceThatFeedsItsDispatcherThroughSink() async {
    let dispatcher = RecordingDispatcher()
    let pipeline = DevicePipeline(
      identifier: Self.identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches([[.leftStick(x: 0.5, y: 0)]]),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    await pipeline.stop()

    #expect(pipeline.origin == .physicalController)
    #expect(pipeline.sink === dispatcher)
    #expect(dispatcher.events().contains { $0.state.leftStick != .center })
  }
}
