import Darwin
import Foundation

/// How an endpoint connection frames its messages on a connected socket.
///
/// `readMessage` runs only on the connection's reading thread; `writeMessage` and `writeClose`
/// run only on its writer queue, except that a transport may answer control frames from the
/// reading thread under its own lock.
protocol EndpointTransport: AnyObject, Sendable {
  /// Blocks until a whole message arrives, the peer closes, or the receive timeout passes.
  func readMessage() -> EndpointReadResult
  /// Writes one message; false when the peer is gone.
  func writeMessage(_ data: Data) -> Bool
  /// Ends the stream after the last message, before the socket shuts down.
  func writeClose()
}

/// The result of reading one message.
enum EndpointReadResult: Equatable {
  /// A whole message.
  case message(Data)
  /// The peer closed the stream.
  case end
  /// The message is longer than the limit.
  case tooLong
  /// A frame the endpoint does not accept, described for the `E1003` error.
  case invalid(String)
}

/// Writes all of `data` to `descriptor`; false when the peer is gone.
func endpointSendAll(_ descriptor: Int32, _ data: Data) -> Bool {
  unsafe data.withUnsafeBytes { buffer in
    guard let base = buffer.baseAddress else { return true }
    var offset = 0
    while offset < buffer.count {
      let sent = unsafe Darwin.send(descriptor, base + offset, buffer.count - offset, 0)
      if sent < 0, errno == EINTR { continue }
      guard sent > 0 else { return false }
      offset += sent
    }
    return true
  }
}

/// JSON lines on the Unix socket.
///
/// - Note: `@unchecked Sendable` because `buffer` is touched only by the reading thread.
final class EndpointLineTransport: EndpointTransport, @unchecked Sendable {
  /// The connected socket.
  private let descriptor: Int32
  /// The bytes read and not yet returned as a line.
  private var buffer = Data()

  /// Creates the transport on `descriptor`.
  init(descriptor: Int32) { self.descriptor = descriptor }

  /// Reads up to the next newline, and returns a line that is not too long as a message.
  func readMessage() -> EndpointReadResult {
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while true {
      if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        return line.count > EndpointServer.maximumLineBytes ? .tooLong : .message(Data(line))
      }
      if buffer.count > EndpointServer.maximumLineBytes { return .tooLong }
      let count = unsafe Darwin.recv(descriptor, &chunk, chunk.count, 0)
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { return .end }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Writes `data` and a newline.
  func writeMessage(_ data: Data) -> Bool {
    endpointSendAll(descriptor, data + [UInt8(ascii: "\n")])
  }

  /// Does nothing; a line stream has no closing frame.
  func writeClose() {}
}
