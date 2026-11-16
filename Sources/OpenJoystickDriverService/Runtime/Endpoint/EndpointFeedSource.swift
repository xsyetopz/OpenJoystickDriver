import Foundation
import OpenJoystickDriverKit

/// A feed client as a source: each `Frame` line it sends goes to the feed's queue through
/// ``VirtualFeedIntakeSink``, and a `KeepAlive` or `Drain` line counts as activity.
///
/// The source also ends the feed when its connection closes and the connection when its feed
/// closes (`E1008`).
/// - Note: `@unchecked Sendable` because `closed` is guarded by `lock`.
final class EndpointFeedSource: InputSource, @unchecked Sendable {
  /// What the feed did with a frame.
  enum Outcome: Equatable, Sendable {
    /// The frame is queued.
    case accepted
    /// The feed's queue is full; the client waits and sends the frame again.
    case full
    /// The feed or its connection is closed.
    case closed
  }

  /// The origin of the input, an endpoint feed.
  let origin = InputOrigin.endpointFeed
  /// The sink that queues the frames of the client.
  let sink: any OutputSink
  /// The registry of the virtual feeds.
  private let feeds: VirtualFeedRegistry
  /// The token of the feed.
  private let token: UUID
  /// The connection of the client.
  private weak var connection: EndpointConnection?
  /// The intake sink, which also counts a keep-alive as activity.
  private let intake: VirtualFeedIntakeSink
  /// The lock that guards `closed`.
  private let lock = NSLock()
  /// Whether the feed was closed.
  private var closed = false

  /// Creates the source for the feed `token` of `connection`.
  init(feeds: VirtualFeedRegistry, token: UUID, connection: EndpointConnection) {
    self.feeds = feeds
    self.token = token
    self.connection = connection
    intake = VirtualFeedIntakeSink(feeds: feeds, token: token)
    sink = intake
  }

  /// Queues `frame` on the feed.
  ///
  /// A closing connection closes the feed, and a closed feed closes the connection with `E1008`.
  func submit(_ frame: VirtualFeedFrame) async -> Outcome {
    guard live() else { return .closed }
    do {
      try await produce(.feed(frame))
      return .accepted
    } catch VirtualFeedIntakeRefusal.queueFull {
      return .full
    } catch {
      feedClosed()
      return .closed
    }
  }

  /// Counts a `KeepAlive` as activity; false once the feed or its connection is closed.
  func keepAlive() -> Bool {
    guard live() else { return false }
    guard intake.keepAlive() else {
      feedClosed()
      return false
    }
    return true
  }

  /// Counts a `Drain` as activity and waits until every frame queued so far has played, the last
  /// for its full time; false once the feed or its connection is closed.
  func drain() async -> Bool {
    guard keepAlive() else { return false }
    guard await feeds.waitUntilPlayed(token: token) else {
      if !Task.isCancelled { feedClosed() }
      return false
    }
    return live()
  }

  /// Watches the feed until the task is cancelled: a connection that is closing closes the feed at
  /// once, though the reader may stay blocked until the connection's writer drains, and a feed
  /// that closed on its own (an idle client, a failed send) closes the connection.
  func watch() async {
    while !Task.isCancelled, live(), feeds.isOpen(token: token) {
      try? await Task.sleep(nanoseconds: ControllerWatchPoller.pollInterval)
    }
    if !Task.isCancelled, !feeds.isOpen(token: token) { feedClosed() }
  }

  /// False once the feed is closed or the connection is closing, which closes the feed.
  private func live() -> Bool {
    lock.withLock {
      guard !closed else { return false }
      guard let connection, !connection.isClosing else {
        closed = true
        Task { [feeds, token] in await feeds.close(token: token) }
        return false
      }
      return true
    }
  }

  /// Closes the connection with `E1008` unless the source is already closed.
  private func feedClosed() {
    let held = lock.withLock { () -> EndpointConnection? in
      guard !closed else { return nil }
      closed = true
      return self.connection
    }
    held?.close(EndpointError(code: .feedClosed, message: "The virtual gamepad closed."))
  }
}

/// Why ``VirtualFeedIntakeSink`` did not queue a frame.
enum VirtualFeedIntakeRefusal: Error, Equatable {
  /// The feed's queue is full.
  case queueFull
  /// No feed has the token.
  case feedClosed
}

/// A feed's frame queue as a sink: the hop from a feed client into the registry.
///
/// A frame joins the queue under the feed's rules (hold, coalescing, bound); the sink throws
/// ``VirtualFeedIntakeRefusal/queueFull`` while the queue has no room, which is the client's
/// backpressure, and `feedClosed` once the feed is gone.
final class VirtualFeedIntakeSink: OutputSink {
  /// The destination of the frames, a virtual device.
  let destination = OutputDestination.virtualDevice
  /// The registry of the virtual feeds.
  private let feeds: VirtualFeedRegistry
  /// The token of the feed.
  private let token: UUID

  /// Creates the sink for the feed `token`.
  init(feeds: VirtualFeedRegistry, token: UUID) {
    self.feeds = feeds
    self.token = token
  }

  /// Queues the feed frame and calls `onDelivered`.
  ///
  /// - Throws: ``VirtualFeedIntakeRefusal`` when the feed is closed or its queue is full, and
  ///   ``StreamBoundaryError/unsupported(_:)`` for a frame that is not a feed frame.
  func consume(
    _ frame: StreamFrame,
    onDelivered: @Sendable () -> Void
  ) async throws {  // swiftlint:disable:this async_without_await
    guard case .feed(let feedFrame) = frame else {
      throw StreamBoundaryError.unsupported(destination)
    }
    let result = feeds.exchange(token: token, frames: [feedFrame])
    if result.closed { throw VirtualFeedIntakeRefusal.feedClosed }
    guard result.accepted > 0 else { throw VirtualFeedIntakeRefusal.queueFull }
    onDelivered()
  }

  /// Counts as activity for the feed's idle timeout and queues nothing; false once it closed.
  func keepAlive() -> Bool { !feeds.exchange(token: token, frames: []).closed }
}

/// The endpoint feed client as the sink of the host's output commands: each rumble command goes
/// to the client as a `RumbleCommand` line, on the connection's bounded queue.
/// - Note: `@unchecked Sendable` because `connection` is weak and only read.
final class EndpointFeedReturnSink: OutputSink, @unchecked Sendable {
  /// The destination of the commands, an endpoint feed client.
  let destination = OutputDestination.endpointFeedClient
  /// The connection of the client.
  private weak var connection: EndpointConnection?

  /// Creates the sink for `connection`.
  init(connection: EndpointConnection) { self.connection = connection }

  /// Sends the rumble line of `command` to the client, and ignores a command that has none.
  ///
  /// - Throws: ``StreamBoundaryError/rejected(_:_:)`` when the connection is closing.
  func consume(
    _ command: ControllerOutputCommand,
    for _: LogicalControllerID
  ) async throws {  // swiftlint:disable:this async_without_await
    guard let connection, !connection.isClosing else {
      throw StreamBoundaryError.rejected(destination, "The connection is closing.")
    }
    // A command with no rumble line, such as a light, is not part of the endpoint's feed.
    guard let line = RumbleCommandLine(command) else { return }
    connection.send(EndpointRumbleCommand(line), bounded: true)
  }
}
