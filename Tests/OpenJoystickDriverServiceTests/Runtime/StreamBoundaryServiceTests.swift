import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The service's paths on the source and sink boundary: feed sinks and origins, the host's
/// feedback returned to a feed client, and the endpoint stream's generation guard.
@Suite(.serialized)
struct StreamBoundaryServiceTests {
  private static let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  /// A connected pair of sockets that raise no `SIGPIPE` when the other end is gone.
  private static func socketPair() -> [Int32] {
    var descriptors: [Int32] = [0, 0]
    unsafe #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    var noSignal: Int32 = 1
    for descriptor in descriptors {
      unsafe setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSignal,
        socklen_t(MemoryLayout<Int32>.size)
      )
    }
    return descriptors
  }

  /// Keeps what a feed's return path delivers, in order.
  private final class RecordingSink: OutputSink, @unchecked Sendable {
    let destination = OutputDestination.endpointFeedClient
    private let lock = NSLock()
    private var commandsValue: [ControllerOutputCommand] = []
    var commands: [ControllerOutputCommand] { lock.withLock { commandsValue } }

    func consume(
      _ command: ControllerOutputCommand,
      for _: LogicalControllerID
    ) async {  // swiftlint:disable:this async_without_await
      lock.withLock { commandsValue.append(command) }
    }
  }

  // MARK: VirtualFeedDeviceSink

  @Test
  func theFeedDeviceSinkSendsGamepadFramesAndReportsThemDelivered() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    _ = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let sink = VirtualFeedDeviceSink(device)
    let delivered = Locked(0)
    let state = RemappingGamepadState(buttons: [.south], axes: [:])

    try await sink.consume(.gamepad(state, for: Self.identifier)) { delivered.withLock { $0 += 1 } }

    #expect(sink.destination == .virtualDevice)
    #expect(device.sent == [state])
    #expect(delivered.withLock { $0 } == 1)
  }

  @Test
  func theFeedDeviceSinkRefusesOtherShapesAndSendsNothing() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    _ = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let sink = VirtualFeedDeviceSink(device)

    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await sink.consume(.activation(Self.identifier)) {}
    }
    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await sink.consume(.feed(VirtualFeedFrame())) {}
    }
    #expect(device.sent.isEmpty)
  }

  @Test
  func aFailedSendDoesNotReportDelivery() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    _ = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    device.failsSending = true
    let delivered = Locked(0)

    await #expect(throws: (any Error).self) {
      try await VirtualFeedDeviceSink(device).consume(
        .gamepad(RemappingGamepadState(), for: Self.identifier)
      ) { delivered.withLock { $0 += 1 } }
    }
    #expect(delivered.withLock { $0 } == 0)
  }

  // MARK: Session origins

  @Test
  func aFeedSessionsOriginFollowsItsPool() async throws {
    let registry = FakeFeedFactory().registry()
    let rpc = try await registry.open(profile: "Generic", pool: .rpc)
    let endpoint = try await registry.open(profile: "Generic", pool: .endpoint)

    #expect(registry.origin(of: rpc.token) == .virtualFeed)
    #expect(registry.origin(of: endpoint.token) == .endpointFeed)
    #expect(registry.origin(of: UUID()) == nil)
    await registry.close(token: rpc.token)
    #expect(registry.origin(of: rpc.token) == nil)
    #expect(registry.isOpen(token: endpoint.token))
    #expect(!registry.isOpen(token: rpc.token))
  }

  // MARK: Host feedback to a feed client

  @Test(.timeLimit(.minutes(1)))
  func feedbackWaitsForTheClientThenArrivesInOrderAndIsNotPolled() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let sink = RecordingSink()
    let session = try await registry.open(profile: "Generic", pool: .endpoint, returnSink: sink)
    let device = try #require(factory.devices.first)
    let commands: [ControllerOutputCommand] = [
      .setRumble(.off, duration: .held), .stopRumble, .setRumble(.off, duration: .held),
    ]
    for command in commands { device.receive(command) }
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(sink.commands.isEmpty)

    registry.startReturningFeedback(token: session.token)
    await waitUntil("sink.commands.count == commands.count") {
      sink.commands.count == commands.count
    }

    #expect(sink.commands == commands)
    #expect(registry.exchange(token: session.token, frames: []).feedback.isEmpty)
    device.receive(.stopRumble)
    await waitUntil("sink.commands.count == commands.count + 1") {
      sink.commands.count == commands.count + 1
    }
    #expect(sink.commands.last == .stopRumble)
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedKeepsTheNewestFeedbackWhenTheClientIsSlowToStart() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let sink = RecordingSink()
    let session = try await registry.open(profile: "Generic", pool: .endpoint, returnSink: sink)
    let device = try #require(factory.devices.first)
    for _ in 0..<44 { device.receive(.setRumble(.off, duration: .held)) }
    for _ in 0..<VirtualFeedRegistry.maximumQueuedFeedback { device.receive(.stopRumble) }

    registry.startReturningFeedback(token: session.token)
    await waitUntil("sink.commands.count == VirtualFeedRegistry.maximumQueuedFeedback") {
      sink.commands.count == VirtualFeedRegistry.maximumQueuedFeedback
    }

    #expect(sink.commands.allSatisfy { $0 == .stopRumble })
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedWithoutAReturnSinkStillReturnsFeedbackToThePoller() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    registry.startReturningFeedback(token: session.token)
    device.receive(.stopRumble)

    #expect(registry.exchange(token: session.token, frames: []).feedback == [.stopRumble])
  }

  @Test(.timeLimit(.minutes(1)))
  func theEndpointReturnSinkWritesARumbleLineAndRefusesAClosingConnection() async throws {
    let descriptors = Self.socketPair()
    try LocalServiceRPCTransport.setTimeout(descriptors[1], seconds: 5)
    defer { close(descriptors[1]) }
    let connection = EndpointConnection(descriptor: descriptors[0])
    let sink = EndpointFeedReturnSink(connection: connection)
    #expect(sink.destination == .endpointFeedClient)

    try await sink.consume(.setRumble(.off, duration: .held), for: Self.identifier)
    var buffer = [UInt8](repeating: 0, count: 4_096)
    let count = unsafe recv(descriptors[1], &buffer, buffer.count, 0)
    let line = String(bytes: buffer.prefix(max(count, 0)), encoding: .utf8) ?? ""
    #expect(line.contains("RumbleCommand"))

    connection.close(nil)
    await #expect(
      throws: StreamBoundaryError.rejected(.endpointFeedClient, "The connection is closing.")
    ) {
      try await sink.consume(.stopRumble, for: Self.identifier)
    }
  }

  // MARK: Client to registry

  @Test(.timeLimit(.minutes(1)))
  func theIntakeSinkQueuesFeedFramesAndRefusesOtherShapesAndClosedFeeds() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic", pool: .endpoint)
    let sink = VirtualFeedIntakeSink(feeds: registry, token: session.token)
    let delivered = Locked(0)

    try await sink.consume(.feed(VirtualFeedFrame(buttons: [.south]))) {
      delivered.withLock { $0 += 1 }
    }
    #expect(delivered.withLock { $0 } == 1)
    let device = try #require(factory.devices.first)
    await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
    await #expect(throws: StreamBoundaryError.unsupported(.virtualDevice)) {
      try await sink.consume(.activation(Self.identifier)) {}
    }
    #expect(sink.keepAlive())

    await registry.close(token: session.token)
    await #expect(throws: VirtualFeedIntakeRefusal.feedClosed) {
      try await sink.consume(.feed(VirtualFeedFrame())) {}
    }
    #expect(!sink.keepAlive())
  }

  @Test(.timeLimit(.minutes(1)))
  func theIntakeSinkPushesBackWhenTheQueueIsFull() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic", pool: .endpoint)
    let device = try #require(factory.devices.first)
    device.hangsSending = true
    defer { device.release() }
    let sink = VirtualFeedIntakeSink(feeds: registry, token: session.token)
    let delivered = Locked(0)
    var refused = false
    for index in 0..<10_000 where !refused {
      let frame = VirtualFeedFrame(
        axes: [.leftStickX: Double(index % 100) / 100],
        holdMilliseconds: 50
      )
      do {
        try await sink.consume(.feed(frame)) { delivered.withLock { $0 += 1 } }
      } catch VirtualFeedIntakeRefusal.queueFull {
        refused = true
      }
    }

    #expect(refused)
    #expect(delivered.withLock { $0 } > 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func aFeedSourceIsAnEndpointFeedOriginAndClosesWithItsFeed() async throws {
    let descriptors = Self.socketPair()
    defer { close(descriptors[1]) }
    let connection = EndpointConnection(descriptor: descriptors[0])
    let registry = FakeFeedFactory().registry()
    let session = try await registry.open(profile: "Generic", pool: .endpoint)
    let source = EndpointFeedSource(feeds: registry, token: session.token, connection: connection)

    #expect(source.origin == .endpointFeed)
    #expect(source.sink.destination == .virtualDevice)
    #expect(await source.submit(VirtualFeedFrame(buttons: [.south])) == .accepted)
    #expect(source.keepAlive())

    await registry.close(token: session.token)
    #expect(await source.submit(VirtualFeedFrame()) == .closed)
    #expect(connection.isClosing)
  }

  // MARK: Endpoint stream generation guard

  @Test
  func anEndpointSubscriberSinkOfAnOlderGenerationDeliversNothing() async throws {
    try await withEndpointServer { server, _ in
      let event = ControllerWatchEvent(
        type: .added,
        object: WatchedController(summary: ControllerSummary(.fixture(id: "pad-1")))
      )
      let generation = server.lock.withLock { server.stream.generation }
      let stale = EndpointSubscribers(server: server, generation: generation - 1)
      let current = EndpointSubscribers(server: server, generation: generation)
      let delivered = Locked(0)

      try await stale.consume(.observed(event)) { delivered.withLock { $0 += 1 } }
      #expect(delivered.withLock { $0 } == 0)
      #expect(server.lock.withLock { server.stream.snapshot.isEmpty })

      try await current.consume(.observed(event)) { delivered.withLock { $0 += 1 } }
      #expect(delivered.withLock { $0 } == 1)
      #expect(server.lock.withLock { server.stream.snapshot.count } == 1)
      await #expect(throws: StreamBoundaryError.unsupported(.endpointSubscription)) {
        try await current.consume(.activation(Self.identifier)) {}
      }
    }
  }
}
