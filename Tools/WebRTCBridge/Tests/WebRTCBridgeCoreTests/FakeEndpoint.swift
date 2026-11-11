import BridgeCore
import Darwin
import Foundation
import WebRTCBridgeCore

/// A stand-in endpoint on a Unix socket.
///
/// It speaks the handshake of `docs/sdk/endpoint.md`, checks the token proof, and then runs one
/// scripted connection. It stops listening after the last expected connection, so a socket scan
/// sees only the bridges.
final class FakeEndpoint: @unchecked Sendable {
  /// The token that the endpoint accepts.
  static let token = "ojd_test_token"
  /// The token name that the endpoint accepts.
  static let tokenName = "bridge"

  /// The path of the socket.
  let path: String
  /// The listening socket, closed by `serve(connections:)`.
  private var listener: Int32 = -1
  /// Guards the recorded frames, requests, proofs and keep-alives.
  private let lock = NSLock()
  /// The `Frame` lines that feeds sent.
  private(set) var framesReceived: [[String: Any]] = []
  /// The first request line of each connection.
  private(set) var requests: [[String: Any]] = []
  /// Whether each `Hello` proof is valid.
  private(set) var proofsValid: [Bool] = []
  /// The count of `KeepAlive` lines.
  private var keepAlives = 0
  /// The lines that a subscription gets after its request.
  let watchLines: [[String: Any]]
  /// The line that a feed gets after its first frame with a button.
  let rumble: [String: Any]
  /// Lines that a feed gets right after its `FeedSession`.
  let feedLines: [[String: Any]]

  /// Binds a listening socket at a path that is unique to the process and the call.
  init(
    watchLines: [[String: Any]] = [],
    rumble: [String: Any] = [:],
    feedLines: [[String: Any]] = []
  ) throws {
    self.watchLines = watchLines
    self.feedLines = feedLines
    self.rumble = rumble
    path = "/tmp/ojd-bridge-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
    listener = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, Darwin.listen(listener, 4) == 0 else { throw BridgeError.socket("bind") }
  }

  /// Serves `count` connections on background threads, then closes the listening socket.
  func serve(connections count: Int) {
    let listener = listener
    Thread.detachNewThread { [self] in
      for _ in 0..<count {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { break }
        Thread.detachNewThread { self.handle(client) }
      }
      Darwin.close(listener)
      unlink(path)
    }
  }

  /// Runs the body under the lock.
  private func record(_ body: () -> Void) {
    lock.lock()
    body()
    lock.unlock()
  }

  /// The frames, requests and proof results recorded so far.
  func snapshot() -> (frames: [[String: Any]], requests: [[String: Any]], proofs: [Bool]) {
    lock.lock()
    defer { lock.unlock() }
    return (framesReceived, requests, proofsValid)
  }

  /// The `KeepAlive` lines that the feed received.
  func keepAliveCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return keepAlives
  }

  /// Writes one JSON line to the client.
  private func write(_ client: Int32, _ line: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
    data.append(0x0A)
    _ = data.withUnsafeBytes { buffer in
      guard let base = buffer.baseAddress else {
        preconditionFailure("A line ends in a newline, so its data is not empty.")
      }
      return Darwin.write(client, base, data.count)
    }
  }

  /// Runs one connection: the handshake, the scripted lines, then waits for the client to close.
  private func handle(_ client: Int32) {
    var pending = Data()
    func next() -> [String: Any]? {
      while true {
        if let newline = pending.firstIndex(of: 0x0A) {
          let text = Data(pending[pending.startIndex..<newline])
          pending.removeSubrange(pending.startIndex...newline)
          return (try? JSONSerialization.jsonObject(with: text)) as? [String: Any]
        }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(client, &chunk, chunk.count)
        if count <= 0 { return nil }
        pending.append(contentsOf: chunk[0..<count])
      }
    }
    let nonce = "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"
    write(client, ["apiVersion": endpointAPIVersion, "kind": "Challenge", "nonce": nonce])
    guard let hello = next(), hello["kind"] as? String == "Hello" else { return }
    let valid =
      hello["proof"] as? String == EndpointSession.proof(token: Self.token, nonce: nonce)
      && hello["tokenName"] as? String == Self.tokenName
    record { proofsValid.append(valid) }
    guard valid else {
      write(
        client,
        [
          "apiVersion": endpointAPIVersion, "kind": "Status", "status": "Failure",
          "code": "E1002", "message": "Not granted.",
        ]
      )
      return
    }
    write(
      client,
      [
        "apiVersion": endpointAPIVersion, "kind": "Welcome", "version": "test",
        "scopes": hello["scopes"] ?? [],
      ]
    )
    guard let request = next() else { return }
    record { requests.append(request) }
    switch request["kind"] as? String {
    case "Subscription":
      for line in watchLines { write(client, line) }
    case "FeedRequest":
      write(
        client,
        [
          "apiVersion": endpointAPIVersion, "kind": "FeedSession",
          "as": request["as"] ?? "Generic",
        ]
      )
      for line in feedLines { write(client, line) }
      var sentRumble = false
      while let line = next() {
        if line["kind"] as? String == "KeepAlive" {
          record { keepAlives += 1 }
          continue
        }
        guard line["kind"] as? String == "Frame" else { continue }
        record { framesReceived.append(line) }
        if !sentRumble && (line["buttons"] as? [String])?.isEmpty == false {
          sentRumble = true
          write(client, rumble)
        }
      }
    default: break
    }
    // Keep a subscription open until the bridge goes away.
    while next() != nil {}
    Darwin.close(client)
  }
}
