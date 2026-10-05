import Darwin
import Foundation
import OpenJoystickDriverKit

/// One endpoint client: messages are read on the caller's thread and written by a serial writer
/// from a bounded queue, framed by the connection's transport.
///
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `lock`.
final class EndpointConnection: @unchecked Sendable {
  private enum Outgoing {
    case message(Data)
    /// A `bounded` line, dropped like an event when the connection closes.
    case feedback(Data)
    case event(ControllerWatchEvent)
  }

  let descriptor: Int32
  let kind: AccessTransport
  private let transport: any EndpointTransport
  private let lock = NSLock()
  private let writer = DispatchQueue(label: "com.openjoystickdriver.endpoint.writer")
  private var pending: [Outgoing] = []
  private var draining = false
  /// Set when the connection sends its last line; nothing is queued after it.
  private var closing = false
  private var welcomed: AccessConnection?
  private var subscribed = false
  private var wantsOutput = false
  /// The last input sent per controller to a client without output, so a poll that changed only
  /// output values sends that client nothing.
  private var lastInput: [String: ControllerState] = [:]

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

  var isSubscribed: Bool { lock.withLock { subscribed && !closing } }
  /// Whether the connection sent its last line or its peer went away.
  var isClosing: Bool { lock.withLock { closing } }
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

  func welcome(_ session: AccessConnection, line: EndpointWelcome) {
    lock.withLock { welcomed = session }
    send(line)
  }

  /// Starts the stream with `snapshot`, the controllers connected before the client subscribed.
  func subscribe(output: Bool, snapshot: [ControllerWatchEvent]) {
    lock.withLock {
      subscribed = true
      wantsOutput = output
    }
    for event in snapshot { deliver(event) }
  }

  /// Queues `line`; a `bounded` line closes the connection with `E1007` when the queue is full
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

  /// Queues `event`, replacing a waiting `input` line of the same controller; closes the
  /// connection with `E1007` when the queue is full.
  func deliver(_ event: ControllerWatchEvent) {
    lock.withLock {
      guard subscribed, !closing else { return }
      var event = event
      if !wantsOutput {
        event.output = nil
        switch event.type {
        case .input:
          guard let input = event.input, lastInput[event.id] != input else { return }
          lastInput[event.id] = input
        case .disconnected: lastInput[event.id] = nil
        case .connected: break
        }
      }
      if event.type == .input,
        let index = pending.lastIndex(where: { Self.controllerID(of: $0) == event.id }),
        case .event(let waiting) = pending[index], waiting.type == .input
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

  private func scheduleDrain() {
    guard !draining else { return }
    draining = true
    writer.async { self.drain() }
  }

  private func drain() {
    let encoder = Self.encoder()
    while true {
      let next = lock.withLock { () -> Outgoing? in
        guard !pending.isEmpty else {
          draining = false
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
    if lock.withLock({ closing }) {
      transport.writeClose()
      shutdown(descriptor, SHUT_RDWR)
    }
  }

  private static func controllerID(of outgoing: Outgoing) -> String? {
    if case .event(let event) = outgoing { event.id } else { nil }
  }

  /// The encoding of `ojd controller watch --json`, so both print the same lines.
  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
