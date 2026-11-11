import CryptoKit
import Darwin
import Foundation

/// The `apiVersion` that every line of the endpoint protocol carries.
public let endpointAPIVersion = "openjoystickdriver/v1alpha3"

/// A failure of the endpoint connection or of the signaling.
public enum BridgeError: Error, CustomStringConvertible, Equatable {
  /// A system call on the endpoint socket failed, or the socket path is unusable.
  case socket(String)
  /// The endpoint answered with a `Status` failure; `code` is its error code.
  case endpoint(code: String, message: String)
  /// The endpoint did not follow the line protocol.
  case protocolViolation(String)
  /// WebRTC signaling failed: the peer connection, the data channel or a blob.
  case signaling(String)

  /// The message of the failure, as `code: message` for an endpoint failure.
  public var description: String {
    switch self {
    case .socket(let text), .protocolViolation(let text), .signaling(let text): return text
    case .endpoint(let code, let message): return "\(code): \(message)"
    }
  }
}

/// A connection to the SDK endpoint's Unix socket after the Challenge, Hello and Welcome lines.
///
/// The session follows `docs/sdk/endpoint.md`: one JSON object per line, a token proof over the
/// challenge, and one request (`Subscription` or `FeedRequest`) after the `Welcome`.
public final class EndpointSession: @unchecked Sendable {
  /// One endpoint line: a decoded JSON object.
  public typealias Line = [String: Any]

  /// The connected socket, closed in `deinit`.
  private let descriptor: Int32
  /// The bytes read from the socket that `readLine` has not returned as a line.
  private var buffer = Data()
  /// Serializes `send`, so two threads never interleave the bytes of two lines.
  private let writeLock = NSLock()

  /// Wraps a connected socket; `connect` runs the handshake on it.
  private init(descriptor: Int32) { self.descriptor = descriptor }

  deinit { Darwin.close(descriptor) }

  /// The proof for a token: HMAC-SHA256 of the four hello lines, keyed with SHA-256 of the token.
  public static func proof(token: String, nonce: String) -> String {
    let message = ["OpenJoystickDriver endpoint hello 1", nonce, "", ""].map { $0 + "\n" }.joined()
    let key = SymmetricKey(data: SHA256.hash(data: Data(token.utf8)))
    let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
    return code.map { String(format: "%02x", $0) }.joined()
  }

  /// Connects to the endpoint's Unix socket and completes the handshake.
  ///
  /// The socket gets `SO_NOSIGPIPE`, so a write to a closed socket fails with an error and does not
  /// raise a signal.
  ///
  /// - Parameters:
  ///   - socketPath: The path of the socket, shorter than `sockaddr_un.sun_path`.
  ///   - token: The access token that keys the proof.
  ///   - tokenName: The name that the `Hello` line gives the token.
  ///   - scopes: The scopes that the `Hello` line asks for.
  /// - Returns: The session, after the `Welcome` line.
  /// - Throws: ``BridgeError`` when the path is too long, the socket cannot connect, or the
  ///   handshake fails.
  public static func connect(
    socketPath: String,
    token: String,
    tokenName: String,
    scopes: [String]
  ) throws -> EndpointSession {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw BridgeError.socket("socket() failed: errno \(errno)") }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard socketPath.utf8.count < capacity else {
      Darwin.close(descriptor)
      throw BridgeError.socket("The socket path is too long.")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { target in
      target.copyBytes(from: socketPath.utf8)
    }
    let status = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard status == 0 else {
      Darwin.close(descriptor)
      throw BridgeError.socket("Cannot connect to \(socketPath): errno \(errno)")
    }
    var noSigPipe: Int32 = 1
    setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_NOSIGPIPE,
      &noSigPipe,
      socklen_t(MemoryLayout<Int32>.size)
    )
    let session = EndpointSession(descriptor: descriptor)
    try session.handshake(token: token, tokenName: tokenName, scopes: scopes)
    return session
  }

  /// Reads the `Challenge`, answers with a `Hello` and its proof, and reads the `Welcome`.
  ///
  /// A `Status` failure in place of the `Welcome` throws the endpoint's error code from `readLine`.
  private func handshake(token: String, tokenName: String, scopes: [String]) throws {
    guard let challenge = try readLine(), challenge["kind"] as? String == "Challenge",
      let nonce = challenge["nonce"] as? String
    else { throw BridgeError.protocolViolation("The endpoint did not send a Challenge.") }
    try send([
      "apiVersion": endpointAPIVersion, "kind": "Hello", "scopes": scopes,
      "tokenName": tokenName, "proof": Self.proof(token: token, nonce: nonce),
    ])
    guard let welcome = try readLine(), welcome["kind"] as? String == "Welcome" else {
      throw BridgeError.protocolViolation("The endpoint did not send a Welcome.")
    }
  }

  /// Writes one JSON object with sorted keys, followed by a newline.
  ///
  /// A lock serializes the writes, so any thread may call it.
  ///
  /// - Throws: ``BridgeError/socket(_:)`` when the write fails, or the encoding error of the line.
  public func send(_ line: Line) throws {
    var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
    data.append(0x0A)
    writeLock.lock()
    defer { writeLock.unlock() }
    var offset = 0
    while offset < data.count {
      let written = data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else {
          preconditionFailure("A line ends in a newline, so its data is not empty.")
        }
        return Darwin.write(descriptor, base + offset, data.count - offset)
      }
      guard written > 0 else { throw BridgeError.socket("Write failed: errno \(errno)") }
      offset += written
    }
  }

  /// Reads the next line of the endpoint, blocking until one arrives.
  ///
  /// - Returns: The line, or nil when the endpoint closed the connection.
  /// - Throws: ``BridgeError/endpoint(code:message:)`` for a `Status` failure, and a protocol
  ///   violation when the line is not a JSON object.
  public func readLine() throws -> Line? {
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        let text = Data(buffer[buffer.startIndex..<newline])
        buffer.removeSubrange(buffer.startIndex...newline)
        guard let object = try JSONSerialization.jsonObject(with: text) as? Line else {
          throw BridgeError.protocolViolation("The endpoint sent a line that is not an object.")
        }
        if object["kind"] as? String == "Status", object["status"] as? String == "Failure" {
          throw BridgeError.endpoint(
            code: object["code"] as? String ?? "unknown",
            message: object["message"] as? String ?? ""
          )
        }
        return object
      }
      var chunk = [UInt8](repeating: 0, count: 16 * 1024)
      let count = Darwin.read(descriptor, &chunk, chunk.count)
      if count < 0 && errno == EINTR { continue }
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Ends the connection and wakes a blocked `readLine`.
  public func close() { Darwin.shutdown(descriptor, SHUT_RDWR) }
}
