import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// Clients read with blocking sockets, so the tests run one at a time to leave the cooperative
/// pool free for the server's poll task.
@Suite(.serialized)
struct EndpointServerTests {
  private static let tool = CodeSigningIdentity(
    kind: .team,
    identifier: "com.example.tool",
    teamIdentifier: "ABCDE12345"
  )
  private static let adHoc = CodeSigningIdentity(
    kind: .adHoc,
    identifier: "a.out",
    teamIdentifier: nil
  )

  @Test
  func aDisabledEndpointHasNoSocket() throws {
    try withServer { server, _ in
      server.start()
      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      let status = try server.status()
      #expect(status.enabled == false)
    }
  }

  @Test
  func disablingRemovesTheSocketAndClosesEveryConnection() throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)
      #expect(try client.readObject()["type"] as? String == "welcome")

      try server.setEnabled(false)

      #expect(try client.readObject()["code"] as? String == "endpoint-disabled")
      #expect(client.readLine() == nil)
      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      #expect(try server.status().enabled == false)
    }
  }

  @Test
  func anUngrantedClientIsRefusedAndListedUntilGranted() throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)

      let line = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
      let refused = try server.status().refused
      #expect(refused.map(\.id) == [Self.tool.accessID])
      #expect(refused.first?.scopes == [.read])

      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      #expect(try server.status().refused.isEmpty)
    }
  }

  @Test
  func anAdHocClientIsRefusedAndCannotBeGranted() throws {
    try withServer(identity: Self.adHoc) { server, _ in
      try server.setEnabled(true)
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(try server.status().refused.map(\.kind) == [.adHoc])
      #expect(throws: AccessGrantStoreError.notGrantable(.adHoc)) {
        try server.grant(Self.adHoc, path: "/a.out", scopes: [.read])
      }
    }
  }

  @Test
  func aGrantedClientStreamsControllerEvents() throws {
    try withServer { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.faceSouth]))
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)
      client.send(#"{"type":"subscribe","stream":"controllers"}"#)

      var lines: [String] = []
      for _ in 0..<3 { lines.append(try #require(client.readLine())) }
      fixture.source.set(devices: [], state: ControllerState(pressed: [.faceSouth]))
      lines.append(try #require(client.readLine()))

      for line in lines {
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      }
      let objects = try lines.map(client.object)
      #expect(
        objects.map { $0["type"] as? String } == ["welcome", "connected", "input", "disconnected"]
      )
      #expect(objects[0]["scopes"] as? [String] == ["read"])
      #expect(objects[1]["id"] as? String == "pad-1")
      #expect(objects[2]["output"] == nil)
      #expect(
        try server.status().connections == [AccessConnection(identity: Self.tool, scopes: [.read])]
      )
    }
  }

  @Test
  func aLateSubscriberFirstReceivesTheConnectedControllers() throws {
    try withServer { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.faceSouth]))
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let first = try EndpointTestClient.subscribed(to: server.socketPath)
      for _ in 0..<2 { _ = try #require(first.readLine()) }

      let second = try EndpointTestClient.subscribed(to: server.socketPath)
      let types = try (0..<2).map { _ in try second.readObject()["type"] as? String }
      #expect(types == ["connected", "input"])
    }
  }

  @Test
  func revokingClosesTheClientsConnections() throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient.subscribed(to: server.socketPath)

      let result = try server.revoke(id: Self.tool.accessID, scopes: nil)

      #expect(
        result == AccessRevokeResult(id: Self.tool.accessID, grant: nil, closedConnections: 1)
      )
      #expect(try client.readObject()["code"] as? String == "revoked")
      #expect(client.readLine() == nil)
    }
  }

  @Test(arguments: [
    (#"{"type":"hello","protocol":2,"scopes":["read"]}"#, "unsupported-protocol"),
    (#"nonsense"#, "invalid-message"),
    (#"{"type":"hello","protocol":1,"scopes":[]}"#, "invalid-message"),
    (#"{"type":"subscribe","stream":"controllers"}"#, "invalid-message"),
    (#"{"type":"hello","protocol":1,"scopes":["read","control"]}"#, "not-granted"),
  ])
  func aBadHelloGetsAnError(hello: String, code: String) throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read, .control])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(hello)

      let line = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      let object = try client.object(line)
      #expect(object["code"] as? String == code)
      #expect((object["supported"] as? [Int]) == (code == "unsupported-protocol" ? [1] : nil))
      #expect(client.readLine() == nil)
    }
  }

  @Test
  func aSecondSubscribeEndsTheConnection() throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient.subscribed(to: server.socketPath)
      client.send(#"{"type":"subscribe","stream":"controllers"}"#)

      #expect(try client.readObject()["code"] as? String == "invalid-message")
      #expect(client.readLine() == nil)
    }
  }

  @Test
  func theNinthConnectionIsRefused() throws {
    try withServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let clients = try (0..<EndpointServer.maximumConnections).map { _ in
        try EndpointTestClient.subscribed(to: server.socketPath)
      }

      let ninth = try EndpointTestClient(path: server.socketPath)

      #expect(try ninth.readObject()["code"] as? String == "too-many-connections")
      #expect(ninth.readLine() == nil)
      _ = clients
    }
  }

  @Test
  func aDamagedFileIsReportedAndKeepsTheEndpointClosed() throws {
    try withServer { server, fixture in
      try FileManager.default.createDirectory(
        at: fixture.directory,
        withIntermediateDirectories: true
      )
      try Data("{".utf8).write(to: fixture.store.url)
      server.start()

      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      #expect(throws: AccessGrantStoreError.damaged) { try server.status() }
      #expect(throws: AccessGrantStoreError.damaged) { try server.setEnabled(true) }
    }
  }

  @Test
  func aStaleSocketFileIsReplaced() throws {
    try withServer { server, fixture in
      try fixture.store.save(AccessGrantFile(enabled: true, grants: []))
      let stale = socket(AF_UNIX, SOCK_STREAM, 0)
      var address = try LocalServiceRPCTransport.socketAddress(path: server.socketPath)
      let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(stale, $0, LocalServiceRPCTransport.socketAddressLength(path: server.socketPath))
        }
      }
      #expect(bound == 0)
      close(stale)

      server.start()

      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)
      #expect(try client.readObject()["code"] as? String == "not-granted")
    }
  }

  private struct Fixture {
    let directory: URL
    let store: AccessGrantStore
    let source: FakeWatchSource
  }

  private func withServer(
    identity: CodeSigningIdentity = tool,
    _ body: (EndpointServer, Fixture) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let fixture = Fixture(
      directory: directory,
      store: AccessGrantStore(directory: directory),
      source: FakeWatchSource()
    )
    let client = EndpointClient(identity: identity, path: "/Tool")
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
}

/// A blocking endpoint client with a 5-second read timeout.
private final class EndpointTestClient {
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
