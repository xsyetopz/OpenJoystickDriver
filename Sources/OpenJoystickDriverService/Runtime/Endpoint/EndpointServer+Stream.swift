import Foundation
import OpenJoystickDriverKit

/// The shared `Controllers` stream: one poll task for every subscriber.
struct EndpointStream {
  /// Bumped on each start, so a cancelled task that is still finishing a poll delivers nothing.
  var generation = 0
  /// The poll task; nil while no connection is subscribed.
  var task: Task<Void, Never>?
  /// The connected controllers in connection order, each as of its last event, for late
  /// subscribers.
  private var controllers: [WatchedController] = []

  /// The events that bring a late subscriber up to date: an `ADDED` with the full current object
  /// of each controller.
  var snapshot: [ControllerWatchEvent] {
    controllers.map { ControllerWatchEvent(type: .added, object: $0) }
  }

  /// Cancels the task and forgets the controllers; the generation stays, so the cancelled task's
  /// last poll is dropped.
  mutating func stop() {
    task?.cancel()
    task = nil
    controllers = []
  }

  /// Applies `event` to the remembered controllers.
  mutating func record(_ event: ControllerWatchEvent) {
    switch event.type {
    case .added: controllers.append(event.object)
    case .modified:
      guard let index = controllers.firstIndex(where: { $0.id == event.id }) else { return }
      controllers[index] = event.object
    case .deleted: controllers.removeAll { $0.id == event.id }
    }
  }
}

extension EndpointServer {
  /// Sends `connection` the connected controllers, then the stream; starts the poll task for the
  /// first subscriber.
  ///
  /// Call with `lock` held.
  func subscribe(_ connection: EndpointConnection, output: Bool) {
    connection.subscribe(output: output, snapshot: stream.snapshot)
    guard stream.task == nil else { return }
    stream.generation += 1
    let generation = stream.generation
    stream.task = Task { [weak self] in await self?.runStream(generation: generation) }
  }

  /// Stops the poll task once no connection is subscribed.
  ///
  /// Call with `lock` held.
  func stopStreamIfIdle() {
    guard stream.task != nil, !connections.values.contains(where: \.isSubscribed) else { return }
    stream.stop()
  }

  /// Polls the controllers until the task is cancelled and delivers each change to the subscribers.
  ///
  /// A stale `generation` delivers nothing. A failed read is printed once until a read
  /// succeeds.
  private func runStream(generation: Int) async {
    var poller = ControllerWatchPoller(source: source)
    let subscribers = EndpointSubscribers(server: self, generation: generation)
    let stream = EndpointStreamSource(sink: subscribers)
    var lastError: String?
    while !Task.isCancelled {
      let includeOutput = lock.withLock { connections.values.contains(where: \.wantsOutputValues) }
      do {
        let updates = try await poller.poll(
          now: DispatchTime.now().uptimeNanoseconds,
          includeOutput: includeOutput
        )
        lastError = nil
        let delivered = Locked([ControllerSessionToken]())
        for update in updates {
          let token = update.device.sessionToken
          let isModification = update.event.type == .modified
          try? await stream.produce(.observed(update.event)) {
            if isModification { delivered.withLock { $0.append(token) } }
          }
        }
        let deliveredAt = DispatchTime.now().uptimeNanoseconds
        for token in delivered.withLock({ $0 }) { await streamDelivered?(token, deliveredAt) }
      } catch {
        if lastError != error.localizedDescription {
          lastError = error.localizedDescription
          print("[EndpointServer] Reading controllers failed: \(error.localizedDescription)")
        }
      }
      try? await Task.sleep(nanoseconds: ControllerWatchPoller.pollInterval)
    }
  }
}

/// The poll of controller state that `Subscription` streams, as the source of its frames.
final class EndpointStreamSource: InputSource {
  /// Marks every frame as coming from the endpoint stream.
  let origin = InputOrigin.endpointStream
  /// The sink that receives the frames.
  let sink: any OutputSink

  /// Creates a source that writes its frames to `sink`.
  init(sink: any OutputSink) { self.sink = sink }
}

/// Every subscribed connection as one sink: a frame is recorded for late subscribers and queued for
/// each connection under the server's lock, so a subscriber's snapshot and its stream never overlap
/// or leave a gap.
///
/// A sink of an older generation, one a restart replaced, delivers nothing.
/// - Note: `@unchecked Sendable` because `server` is weak and only read.
final class EndpointSubscribers: OutputSink, @unchecked Sendable {
  /// Marks the frames as delivered to endpoint subscriptions.
  let destination = OutputDestination.endpointSubscription
  /// The server whose connections receive the frames; weak so the sink does not keep it alive.
  private weak var server: EndpointServer?
  /// The stream generation this sink belongs to.
  private let generation: Int

  /// Creates a sink of `server` for the stream of `generation`.
  init(server: EndpointServer, generation: Int) {
    self.server = server
    self.generation = generation
  }

  /// Records an observed `frame` and queues it for every connection.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)`` for a frame that is not an observed
  ///   event.
  func consume(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void
  ) async throws {  // swiftlint:disable:this async_without_await
    guard case .observed(let event) = frame else {
      throw StreamBoundaryError.unsupported(destination)
    }
    guard let server else { return }
    let delivered = server.lock.withLock {
      guard server.stream.generation == generation else { return false }
      server.stream.record(event)
      for connection in server.connections.values { connection.deliver(event) }
      return true
    }
    if delivered { onDelivered() }
  }
}
