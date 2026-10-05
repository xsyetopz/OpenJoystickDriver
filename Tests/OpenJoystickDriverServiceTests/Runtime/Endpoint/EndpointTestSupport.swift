import CryptoKit
import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct EndpointFixture {
  static let tool = CodeSigningIdentity(
    kind: .team,
    identifier: "com.example.tool",
    teamIdentifier: "ABCDE12345"
  )

  let directory: URL
  let store: AccessGrantStore
  let source: FakeWatchSource

  var pagesDirectory: URL { directory.appendingPathComponent("Overlays", isDirectory: true) }
}

/// Runs `body` with an endpoint on a private socket whose clients have `identity`; nil makes
/// every signature unreadable.
func withEndpointServer(
  identity: CodeSigningIdentity? = EndpointFixture.tool,
  _ body: (EndpointServer, EndpointFixture) throws -> Void
) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  let fixture = EndpointFixture(
    directory: directory,
    store: AccessGrantStore(directory: directory),
    source: FakeWatchSource()
  )
  let client = identity.map { EndpointClient(identity: $0, path: "/Tool") }
  let server = EndpointServer(
    socketPath: FileManager.default.temporaryDirectory.path
      + "/ojd-\(UUID().uuidString.prefix(8)).sock",
    store: fixture.store,
    source: fixture.source,
    version: "1.2.3"
  ) { _ in client }
  defer {
    server.stop()
    try? FileManager.default.removeItem(at: directory)
  }
  try body(server, fixture)
}

/// The `hello` of a token client, with the proof the endpoint documents: HMAC-SHA256, keyed with
/// the token's SHA-256, of the domain line, the nonce, the origin, and the port, each ended with a
/// newline; the origin and the port are empty on the Unix socket.
func tokenHello(
  name: String,
  token: String,
  nonce: String,
  origin: String = "",
  port: String = "",
  scopes: [String] = ["read"]
) -> String {
  let key = SymmetricKey(data: SHA256.hash(data: Data(token.utf8)))
  let message = ["OpenJoystickDriver endpoint hello 1", nonce, origin, port]
    .map { $0 + "\n" }.joined()
  let proof = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
    .map { String(format: "%02x", $0) }.joined()
  let scopes = scopes.map { #""\#($0)""# }.joined(separator: ",")
  return #"{"type":"hello","protocol":1,"scopes":[\#(scopes)],"tokenName":"\#(name)","#
    + #""proof":"\#(proof)"}"#
}

/// A blocking endpoint client with a 5-second read timeout.
final class EndpointTestClient {
  /// The nonce of the challenge that the service sent first.
  private(set) var nonce = ""
  private let descriptor: Int32
  private var buffer = Data()

  init(path: String) throws {
    descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: path)
    let status = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(descriptor, $0, LocalServiceRPCTransport.socketAddressLength(path: path))
      }
    }
    guard status == 0 else {
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 5)
    let challenge = try readObject()
    #expect(challenge["type"] as? String == "challenge")
    nonce = challenge["nonce"] as? String ?? ""
  }

  deinit { close(descriptor) }

  /// A client that said hello, read its welcome, and subscribed to controllers.
  static func subscribed(to path: String) throws -> EndpointTestClient {
    let client = try EndpointTestClient(path: path)
    client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)
    guard try client.readObject()["type"] as? String == "welcome" else {
      throw POSIXError(.EPROTO)
    }
    client.send(#"{"type":"subscribe","stream":"controllers"}"#)
    return client
  }

  func send(_ line: String) {
    let data = Data((line + "\n").utf8)
    _ = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
  }

  /// The next line, or nil when the service closed the connection or the timeout passed.
  func readLine() -> String? {
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while true {
      if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        let line = String(bytes: buffer[buffer.startIndex..<newline], encoding: .utf8) ?? ""
        buffer.removeSubrange(buffer.startIndex...newline)
        return line
      }
      let count = recv(descriptor, &chunk, chunk.count, 0)
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  func readObject() throws -> [String: Any] {
    try object(try #require(readLine()))
  }

  func object(_ line: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
  }
}

/// A blocking HTTP and WebSocket client on `127.0.0.1` with a 5-second read timeout, written
/// against RFC 6455 so the tests control every header and frame.
final class EndpointWebTestClient {
  struct Response {
    let status: Int
    /// Lowercased names.
    let headers: [String: String]
    let body: Data
  }

  /// The nonce of the challenge, once `readChallenge` read it.
  private(set) var nonce = ""
  static let key = "dGhlIHNhbXBsZSBub25jZQ=="

  private let descriptor: Int32
  private var buffer = Data()

  init(port: Int, address: String = "127.0.0.1") throws {
    descriptor = socket(AF_INET, SOCK_STREAM, 0)
    var socketAddress = sockaddr_in()
    socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    socketAddress.sin_family = sa_family_t(AF_INET)
    socketAddress.sin_port = in_port_t(UInt16(port).bigEndian)
    inet_pton(AF_INET, address, &socketAddress.sin_addr)
    let status = withUnsafePointer(to: &socketAddress) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard status == 0 else {
      let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      close(descriptor)
      throw error
    }
    var noSignal: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 5)
  }

  deinit { close(descriptor) }

  /// The headers of a browser's upgrade to the endpoint; nil values are left out.
  static func upgradeHeaders(port: Int, origin: String?) -> [String: String?] {
    [
      "Host": "127.0.0.1:\(port)", "Origin": origin, "Upgrade": "websocket",
      "Connection": "Upgrade", "Sec-WebSocket-Key": key, "Sec-WebSocket-Version": "13",
    ]
  }

  /// A client that upgraded with `origin`, answered the challenge for the token `name`, and read
  /// `welcome`.
  static func welcomed(
    port: Int,
    origin: String,
    name: String = "overlay",
    token: String
  ) throws -> EndpointWebTestClient {
    let client = try EndpointWebTestClient(port: port)
    let response = try #require(
      client.request("/endpoint", headers: upgradeHeaders(port: port, origin: origin))
    )
    #expect(response.status == 101)
    try client.readChallenge()
    client.send(
      tokenHello(name: name, token: token, nonce: client.nonce, origin: origin, port: String(port))
    )
    #expect(try client.readObject()["type"] as? String == "welcome")
    return client
  }

  /// Sends a request and reads the response head, and the body unless it is an upgrade.
  func request(
    _ path: String,
    method: String = "GET",
    headers: [String: String?]
  ) -> Response? {
    var text = "\(method) \(path) HTTP/1.1\r\n"
    for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
      if let value { text += "\(name): \(value)\r\n" }
    }
    sendBytes(Data((text + "\r\n").utf8))
    let end = Data("\r\n\r\n".utf8)
    var found = buffer.range(of: end)
    while found == nil {
      guard receive() else { return nil }
      found = buffer.range(of: end)
    }
    guard let range = found,
      let head = String(bytes: buffer[buffer.startIndex..<range.lowerBound], encoding: .utf8)
    else { return nil }
    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
    let lines = head.components(separatedBy: "\r\n")
    let status = Int(lines[0].split(separator: " ")[1]) ?? 0
    var fields: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      fields[line[..<colon].lowercased()] = line[line.index(after: colon)...]
        .trimmingCharacters(in: .whitespaces)
    }
    guard status != 101 else { return Response(status: status, headers: fields, body: Data()) }
    while receive() {}
    defer { buffer.removeAll() }
    return Response(status: status, headers: fields, body: buffer)
  }

  /// Sends one masked text frame.
  func send(_ text: String) { sendFrame(opcode: 0x1, payload: Data(text.utf8)) }

  func sendFrame(opcode: UInt8, payload: Data, final: Bool = true, masked: Bool = true) {
    var frame = Data([(final ? 0x80 : 0) | opcode])
    let maskBit: UInt8 = masked ? 0x80 : 0
    switch payload.count {
    case 0..<126: frame.append(maskBit | UInt8(payload.count))
    case 126..<65_536:
      frame.append(maskBit | 126)
      frame.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian, Array.init))
    default:
      frame.append(maskBit | 127)
      frame.append(contentsOf: withUnsafeBytes(of: UInt64(payload.count).bigEndian, Array.init))
    }
    guard masked else {
      sendBytes(frame + payload)
      return
    }
    let mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]
    frame.append(contentsOf: mask)
    frame.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
    sendBytes(frame)
  }

  /// The next frame from the service, which must not be masked; nil when the connection ended.
  func readFrame() -> (opcode: UInt8, payload: Data)? {
    while true {
      if buffer.count >= 2 {
        let bytes = [UInt8](buffer.prefix(10))
        #expect(bytes[1] & 0x80 == 0)
        var length = Int(bytes[1] & 0x7F)
        var offset = 2
        if length == 126, bytes.count >= 4 {
          length = Int(bytes[2]) << 8 | Int(bytes[3])
          offset = 4
        } else if length == 127, bytes.count >= 10 {
          length = bytes[2..<10].reduce(0) { $0 << 8 | Int($1) }
          offset = 10
        }
        if length < 126 || offset > 2, buffer.count >= offset + length {
          let start = buffer.startIndex
          let payload = Data(buffer[(start + offset)..<(start + offset + length)])
          buffer.removeSubrange(start..<(start + offset + length))
          return (bytes[0] & 0x0F, payload)
        }
      }
      guard receive() else { return nil }
    }
  }

  /// Reads the challenge that follows the upgrade and keeps its nonce.
  func readChallenge() throws {
    let challenge = try readObject()
    #expect(challenge["type"] as? String == "challenge")
    nonce = challenge["nonce"] as? String ?? ""
  }

  /// The next text message; nil at a close frame or the end of the connection.
  func readLine() -> String? {
    while let frame = readFrame() {
      switch frame.opcode {
      case 0x1: return String(bytes: frame.payload, encoding: .utf8)
      case 0x8: return nil
      default: continue
      }
    }
    return nil
  }

  func readObject() throws -> [String: Any] {
    try object(try #require(readLine()))
  }

  func object(_ line: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
  }

  /// The `Sec-WebSocket-Accept` value for `key`, from RFC 6455.
  static func accept(for key: String) -> String {
    let text = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return Data(Insecure.SHA1.hash(data: Data(text.utf8))).base64EncodedString()
  }

  func sendBytes(_ data: Data) {
    _ = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
  }

  private func receive() -> Bool {
    var chunk = [UInt8](repeating: 0, count: 65_536)
    let count = recv(descriptor, &chunk, chunk.count, 0)
    guard count > 0 else { return false }
    buffer.append(contentsOf: chunk[0..<count])
    return true
  }
}
