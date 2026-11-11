import Foundation
import OpenJoystickDriverKit

extension EndpointServer {
  /// Runs a `feed` on the connection's thread: opens a virtual gamepad, applies each frame line to
  /// it, and sends the host's rumble commands as lines until either side closes.
  ///
  /// A pump exchanges with the feed each poll to send rumble, but that does not count as activity:
  /// a feed whose client sends no frame line for ``VirtualFeedExchangeResult/idleTimeoutSeconds``
  /// is closed with `E1008`, so a stalled client does not hold a button or a slot. A `KeepAlive`
  /// line counts as activity and does nothing else. A `Drain` line counts as activity, and the
  /// feed answers `Drained` once the frames before it have played; reading waits meanwhile, and
  /// the queued frames keep the feed from going idle. When the feed's frame queue is full,
  /// reading waits, which pushes back on the client.
  /// A client that closes the connection meanwhile ends the feed, though its unread lines wait.
  func feed(_ connection: EndpointConnection, persona: VirtualHIDProfileID) {
    guard let feeds else {
      connection.close(
        EndpointError(code: .feedClosed, message: "The service runs no virtual gamepads.")
      )
      return
    }
    let token: UUID
    do {
      token = try Self.waitFor(connection) {
        try await feeds.open(
          profile: persona.rawValue,
          pool: .endpoint,
          returnSink: EndpointFeedReturnSink(connection: connection)
        ).token
      }
    } catch {
      connection.close(Self.feedError(error, persona: persona))
      return
    }
    let source = EndpointFeedSource(feeds: feeds, token: token, connection: connection)
    let watch = Task { await source.watch() }
    defer {
      watch.cancel()
      Task { await feeds.close(token: token) }
    }
    connection.send(EndpointFeedSession(as: persona))
    feeds.startReturningFeedback(token: token)

    while true {
      switch connection.readMessage() {
      case .end: return
      case .tooLong:
        connection.close(Self.invalid("A message is longer than \(Self.maximumLineBytes) bytes."))
        return
      case .invalid(let reason):
        connection.close(Self.invalid(reason))
        return
      case .message(let data):
        let frame: VirtualFeedFrame
        switch Self.feedLine(data) {
        case .success(.keepAlive):
          if !source.keepAlive() { return }
          continue
        case .success(.drain):
          let drained = (try? Self.waitFor(connection) { await source.drain() }) ?? false
          if !drained { return }
          connection.send(EndpointDrained())
          continue
        case .success(.frame(let decoded)): frame = decoded
        case .failure(let refusal):
          connection.close(refusal)
          return
        }
        while true {
          let outcome = (try? Self.waitFor(connection) { await source.submit(frame) }) ?? .closed
          if outcome == .closed { return }
          if outcome == .accepted { break }
          if connection.peerHungUp { return }
          usleep(useconds_t(VirtualFeedExchangeResult.minimumFrameMilliseconds * 1_000))
        }
      }
    }
  }

  /// A line that a feed accepts after `FeedSession`.
  private enum FeedLine {
    /// A `Frame` line with its decoded frame.
    case frame(VirtualFeedFrame)
    /// `KeepAlive`: it resets the idle timeout and changes nothing else.
    case keepAlive
    /// `Drain`: the endpoint answers `Drained` once the frames sent before it have played.
    case drain
  }

  /// The `Frame`, `KeepAlive` or `Drain` on the line, or the error that refuses the line: the
  /// header errors of ``EndpointHeader``, or `E1003` for a `Frame` that does not decode and a
  /// `KeepAlive` or `Drain` that has a member besides `apiVersion` and `kind`.
  ///
  /// ``VirtualFeedFrame`` takes the envelope as optional for the CLI's stdin lines, so the header
  /// is checked first.
  private static func feedLine(_ data: Data) -> Result<FeedLine, EndpointError> {
    let accepted = [VirtualFeedFrame.kind, "KeepAlive", "Drain"]
    if let refusal = EndpointHeader.refusal(of: data, accepting: accepted) {
      return .failure(refusal)
    }
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if let kind = object?["kind"] as? String, kind == "KeepAlive" || kind == "Drain" {
      guard object?.count == 2 else {
        return .failure(invalid("\(kind) has no member besides apiVersion and kind."))
      }
      return .success(kind == "Drain" ? .drain : .keepAlive)
    }
    guard let frame = try? JSONDecoder().decode(VirtualFeedFrame.self, from: data) else {
      return .failure(invalid("Send Frame lines that match the endpoint schema after FeedSession."))
    }
    return .success(.frame(frame))
  }

  /// Maps a failure of the feed to the error that the endpoint reports for `persona`.
  private static func feedError(_ error: any Error, persona: VirtualHIDProfileID) -> EndpointError {
    switch error as? VirtualFeedError {
    case .unknownProfile:
      invalid("\(persona.rawValue) is not a persona the service publishes.")
    case .tooManyFeeds(let limit):
      EndpointError(
        code: .tooManyFeeds,
        message: "The service already runs \(limit) virtual gamepads."
      )
    default:
      EndpointError(
        code: .feedClosed,
        message: "The virtual gamepad did not start: \(error.localizedDescription)"
      )
    }
  }

  /// Runs `work` and blocks the calling thread, a connection-queue thread, until it finishes;
  /// cancels `work` once `connection` is closing or its peer hung up.
  static func waitFor<T: Sendable>(
    _ connection: EndpointConnection,
    _ work: @escaping @Sendable () async throws -> T
  ) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    let task = Task {
      do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
      done.signal()
    }
    let poll = DispatchTimeInterval.nanoseconds(Int(ControllerWatchPoller.pollInterval))
    while done.wait(timeout: .now() + poll) == .timedOut {
      if connection.isClosing || connection.peerHungUp { task.cancel() }
    }
    guard let result = box.result else {
      preconditionFailure("the semaphore signals only after the task stores its result")
    }
    return try result.get()
  }
}

/// Written by one task before the semaphore signals, read after it.
/// - Note: `@unchecked Sendable` because the semaphore orders the write before the read.
private final class ResultBox<T>: @unchecked Sendable {
  /// The outcome of the work, set by the task that ran it.
  var result: Result<T, any Error>?
}
