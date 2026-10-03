import Darwin
import Foundation
import OpenJoystickDriverKit

/// One endpoint client: lines are read on the caller's thread and written by a serial writer from
/// a bounded queue.
///
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `lock`, except
///   `buffer`, which only the reading thread touches.
final class EndpointConnection: @unchecked Sendable {
  enum ReadResult: Equatable {
    case line(Data)
    case end
    case tooLong
  }

  private enum Outgoing {
    case message(Data)
    case event(ControllerWatchEvent)
  }

  let descriptor: Int32
  private let lock = NSLock()
  private let writer = DispatchQueue(label: "com.openjoystickdriver.endpoint.writer")
  private var pending: [Outgoing] = []
  private var draining = false
  /// Set when the connection sends its last line; nothing is queued after it.
  private var closing = false
  private var welcomed: EndpointClient?
  private var grantedScopes: [EndpointScope] = []
  private var subscribed = false
  private var wantsOutput = false
  /// The last input sent per controller to a client without output, so a poll that changed only
  /// output values sends that client nothing.
  private var lastInput: [String: ControllerState] = [:]
  private var buffer = Data()

  init(descriptor: Int32) { self.descriptor = descriptor }

  /// The client and its scopes once the handshake succeeded.
  var session: (client: EndpointClient, scopes: [EndpointScope])? {
    lock.withLock { welcomed.map { ($0, grantedScopes) } }
  }

  var isSubscribed: Bool { lock.withLock { subscribed && !closing } }
  var wantsOutputValues: Bool { lock.withLock { subscribed && wantsOutput && !closing } }

  /// Reads the next line without its newline; blocks until one arrives, the peer closes, or the
  /// receive timeout passes.
  func readLine() -> ReadResult {
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while true {
      if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        return line.count > EndpointServer.maximumLineBytes ? .tooLong : .line(Data(line))
      }
      if buffer.count > EndpointServer.maximumLineBytes { return .tooLong }
      let count = Darwin.recv(descriptor, &chunk, chunk.count, 0)
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { return .end }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Blocks reads for at most `seconds`; zero waits without a limit.
  func setReceiveTimeout(seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  func welcome(_ client: EndpointClient, scopes: [EndpointScope], line: EndpointWelcome) {
    lock.withLock {
      welcomed = client
      grantedScopes = scopes
    }
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

  func send(_ line: some Encodable) {
    guard let data = try? Self.encoder().encode(line) else { return }
    lock.withLock {
      guard !closing else { return }
      pending.append(.message(data))
      scheduleDrain()
    }
  }

  /// Queues `event`, replacing a waiting `input` line of the same controller; closes the
  /// connection with `too-slow` when the queue is full.
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
    pending.removeAll()
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
      case .message(let message): data = message
      case .event(let event):
        guard let encoded = try? encoder.encode(event) else { continue }
        data = encoded
      }
      guard write(data + [UInt8(ascii: "\n")]) else {
        lock.withLock {
          closing = true
          pending.removeAll()
          draining = false
        }
        shutdown(descriptor, SHUT_RDWR)
        return
      }
    }
    if lock.withLock({ closing }) { shutdown(descriptor, SHUT_RDWR) }
  }

  private func write(_ data: Data) -> Bool {
    data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let sent = Darwin.send(descriptor, buffer.baseAddress! + offset, buffer.count - offset, 0)
        if sent < 0, errno == EINTR { continue }
        guard sent > 0 else { return false }
        offset += sent
      }
      return true
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
