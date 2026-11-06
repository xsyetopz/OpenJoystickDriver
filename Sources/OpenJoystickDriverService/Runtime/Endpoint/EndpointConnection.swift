import Darwin
import Foundation
import OpenJoystickDriverKit

/// One endpoint client: messages are read on the caller's thread and written by a serial writer
/// from a bounded queue, framed by the connection's transport.
///
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `lock`.
final class EndpointConnection: @unchecked Sendable {
  /// A line waiting to be written.
  private enum Outgoing {
    /// A line that is always written.
    case message(Data)
    /// A `bounded` line, dropped like an event when the connection closes.
    case feedback(Data)
    /// A controller event.
    case event(ControllerWatchEvent)
  }

  /// The connected socket.
  let descriptor: Int32
  /// The transport the client connected through.
  let kind: AccessTransport
  /// The framing of the messages.
  private let transport: any EndpointTransport
  /// The lock that guards the queue and the flags.
  private let lock = NSLock()
  /// The serial queue that writes the lines.
  private let writer = DispatchQueue(label: "com.openjoystickdriver.endpoint.writer")
  /// The lines waiting to be written.
  private var pending: [Outgoing] = []
  /// Whether a drain of the queue is scheduled.
  private var draining = false
  /// Set when the connection sends its last line; nothing is queued after it.
  private var closing = false
  /// The client and its scopes, once the handshake succeeded.
  private var welcomed: AccessConnection?
  /// Whether the client subscribed to the controller stream.
  private var subscribed = false
  /// Whether the subscription adds the output values.
  private var wantsOutput = false
  /// The last input sent per controller to a client without output, so a poll that changed only
  /// output values sends that client nothing.
  private var lastInput: [String: ControllerState] = [:]

  /// Creates the connection on `descriptor`.
  init(descriptor: Int32, kind: AccessTransport, transport: any EndpointTransport) {
    self.descriptor = descriptor
    self.kind = kind
    self.transport = transport
  }

  /// A connection on the Unix socket.
  convenience init(descriptor: Int32) {
    self.init(
      descriptor: descriptor,
      kind: .socket,
      transport: EndpointLineTransport(descriptor: descriptor)
    )
  }

  /// The client and its scopes once the handshake succeeded.
  var session: AccessConnection? { lock.withLock { welcomed } }

  /// Whether the client subscribed and the connection is open.
  var isSubscribed: Bool { lock.withLock { subscribed && !closing } }
  /// Whether the connection sent its last line or its peer went away.
  var isClosing: Bool { lock.withLock { closing } }
  /// Whether the client subscribed with output values and the connection is open.
  var wantsOutputValues: Bool { lock.withLock { subscribed && wantsOutput && !closing } }

  /// Whether the peer closed or shut down its side, even while unread messages wait.
  var peerHungUp: Bool {
    var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    return poll(&entry, 1, 0) > 0 && entry.revents & Int16(POLLHUP | POLLERR) != 0
  }

  /// Reads the next message; blocks until one arrives, the peer closes, or the receive timeout
  /// passes.
  func readMessage() -> EndpointReadResult { transport.readMessage() }

  /// Blocks reads for at most `seconds`; zero waits without a limit.
  func setReceiveTimeout(seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  /// Stores `session` and sends the `Welcome` line `line`.
  func welcome(_ session: AccessConnection, line: EndpointWelcome) {
    lock.withLock { welcomed = session }
    send(line)
  }

  /// Starts the stream with `snapshot`, an `ADDED` event with the current object of each
  /// controller connected before the client subscribed.
  func subscribe(output: Bool, snapshot: [ControllerWatchEvent]) {
    lock.withLock {
      subscribed = true
      wantsOutput = output
    }
    for event in snapshot { deliver(event) }
  }

  /// Queues `line`; a `bounded` line closes the connection with `E1006` when the queue is full
  /// and is dropped when the connection closes first.
  func send(_ line: some Encodable, bounded: Bool = false) {
    guard let data = try? Self.encoder().encode(line) else { return }
    lock.withLock {
      guard !closing else { return }
      guard !bounded || pending.count < EndpointServer.maximumQueuedLines else {
        closeLocked(EndpointError(code: .tooSlow, message: "The client read too slowly."))
        return
      }
      pending.append(bounded ? .feedback(data) : .message(data))
      scheduleDrain()
    }
  }

  /// Queues `event`, replacing a waiting `MODIFIED` line of the same controller; closes the
  /// connection with `E1006` when the queue is full.
  func deliver(_ event: ControllerWatchEvent) {
    lock.withLock {
      guard subscribed, !closing else { return }
      var event = event
      if !wantsOutput {
        event.object.output = nil
        switch event.type {
        case .modified:
          guard let input = event.object.input, lastInput[event.id] != input else { return }
          lastInput[event.id] = input
        case .deleted: lastInput[event.id] = nil
        case .added: lastInput[event.id] = event.object.input
        }
      }
      if event.type == .modified,
        let index = pending.lastIndex(where: { Self.controllerID(of: $0) == event.id }),
        case .event(let waiting) = pending[index], waiting.type == .modified
      {
        pending[index] = .event(event)
        return
      }
      guard pending.count < EndpointServer.maximumQueuedLines else {
        closeLocked(EndpointError(code: .tooSlow, message: "The client read too slowly."))
        return
      }
      pending.append(.event(event))
      scheduleDrain()
    }
  }

  /// Sends `error`, if any, as the last line, then shuts the socket down.
  func close(_ error: EndpointError?) { lock.withLock { closeLocked(error) } }

  /// Ends the connection after its reader stopped; queued lines are still written, then the
  /// descriptor closes.
  func finish() {
    lock.withLock { closing = true }
    writer.async {
      shutdown(self.descriptor, SHUT_RDWR)
      Darwin.close(self.descriptor)
    }
  }

  // MARK: - Private

  /// Queues `error` as the last line, drops the waiting events and feedback lines, and closes.
  ///
  /// Call with `lock` held.
  private func closeLocked(_ error: EndpointError?) {
    guard !closing else { return }
    // Events and rumble lines waiting behind the error are dropped; the challenge and welcome
    // are kept.
    pending.removeAll {
      if case .message = $0 { false } else { true }
    }
    if let error, let data = try? Self.encoder().encode(error) { pending.append(.message(data)) }
    closing = true
    scheduleDrain()
  }

  /// Starts a drain of the queue on the writer queue, unless one is scheduled.
  private func scheduleDrain() {
    guard !draining else { return }
    draining = true
    writer.async { self.drain() }
  }

  /// Writes the queued lines in order and shuts the socket down after the last line of a closing
  /// connection.
  ///
  /// A failed write closes the connection and drops the queue.
  private func drain() {
    let encoder = Self.encoder()
    // `closing` is read in the same lock that ends the drain: a close that queues its error after
    // that point starts the next drain, which then owns the shutdown.
    var closed = false
    while true {
      let next = lock.withLock { () -> Outgoing? in
        guard !pending.isEmpty else {
          draining = false
          closed = closing
          return nil
        }
        return pending.removeFirst()
      }
      guard let next else { break }
      let data: Data
      switch next {
      case .message(let message), .feedback(let message): data = message
      case .event(let event):
        guard let encoded = try? encoder.encode(event) else { continue }
        data = encoded
      }
      guard transport.writeMessage(data) else {
        lock.withLock {
          closing = true
          pending.removeAll()
          draining = false
        }
        shutdown(descriptor, SHUT_RDWR)
        return
      }
    }
    if closed {
      transport.writeClose()
      shutdown(descriptor, SHUT_RDWR)
    }
  }

  /// Returns the controller ID of the event `outgoing`, or nil for another line.
  private static func controllerID(of outgoing: Outgoing) -> String? {
    if case .event(let event) = outgoing { event.id } else { nil }
  }

  /// The encoding of `ojd controller watch --all --json`, so both print the same lines.
  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
