import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// Clients read with blocking sockets that run off the cooperative pool, so the pool stays free
/// for the server's poll task.
@Suite(.serialized)
struct EndpointServerTests {
  private static let tool = CodeSigningIdentity(
    kind: .signed,
    identifier: "com.example.tool",
    publisherID: "ABCDE12345"
  )
  private static let adHoc = CodeSigningIdentity(
    kind: .adHoc,
    identifier: "a.out",
    publisherID: nil
  )

  @Test
  func aDisabledEndpointHasNoSocket() async throws {
    try await withEndpointServer { server, _ in
      server.start()
      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      let status = try server.status()
      #expect(status.enabled == false)
    }
  }

  @Test
  func disablingRemovesTheSocketAndClosesEveryConnection() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")

      try server.setEnabled(false)

      #expect(try await client.readObject()["code"] as? String == "E1001")
      #expect(await client.readLine() == nil)
      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      #expect(try server.status().enabled == false)
    }
  }

  @Test
  func aDisableAndEnableCycleLeavesOneAcceptLoop() async throws {
    try await withEndpointServer { server, _ in
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      for _ in 0..<5 {
        try server.setEnabled(true)
        try server.setEnabled(false)
      }
      try server.setEnabled(true)

      await waitUntil("the stale accept loops end") { server.socketAcceptLoopCount == 1 }
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      #expect(server.socketAcceptLoopCount == 1)
    }
  }

  /// Connects to the socket and leaves the connection unread, which makes the listener readable
  /// while the accept calls of these tests fail.
  private static func connectWithoutHandshake(_ path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: path)
    let length = LocalServiceRPCTransport.socketAddressLength(path: path)
    let status = withUnsafePointer(to: &address) {
      unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe connect(descriptor, $0, length)
      }
    }
    try #require(status == 0)
    return descriptor
  }

  /// Collects the lines an accept loop reports.
  private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
  }

  @Test
  func stoppingTheEndpointDuringAWaitForResourcesEndsTheLoopAtOnce() async throws {
    let reports = Reports()
    let failing: @Sendable (Int32) -> Int32 = { _ in
      errno = EMFILE
      return -1
    }
    try await withEndpointServer(
      acceptCall: failing,
      resourceWaitMilliseconds: 600_000,
      report: reports.add
    ) { server, _ in
      try server.setEnabled(true)
      let client = try Self.connectWithoutHandshake(server.socketPath)
      defer { Darwin.close(client) }
      await waitUntil("the loop reports the wait") { !reports.all.isEmpty }
      #expect(reports.all.first?.contains("Cannot accept connections") == true)

      try server.setEnabled(false)
      await waitUntil("the loop ends") { server.socketAcceptLoopCount == 0 }
      #expect(reports.all.count == 1)
    }
  }

  @Test
  func aNormalStopReportsNoAcceptFailure() async throws {
    let reports = Reports()
    let inAccept = DispatchSemaphore(value: 0)
    let proceed = DispatchSemaphore(value: 0)
    // The listener is stopped while the loop is here; the call then fails as it does on the
    // placeholder that replaced the socket.
    let stoppedMeanwhile: @Sendable (Int32) -> Int32 = { _ in
      inAccept.signal()
      proceed.wait()
      errno = ENOTSOCK
      return -1
    }
    try await withEndpointServer(
      acceptCall: stoppedMeanwhile,
      report: reports.add
    ) { server, _ in
      try server.setEnabled(true)
      let client = try Self.connectWithoutHandshake(server.socketPath)
      defer { Darwin.close(client) }
      await offPool { inAccept.wait() }

      try server.setEnabled(false)
      proceed.signal()
      await waitUntil("the loop ends") { server.socketAcceptLoopCount == 0 }
      #expect(reports.all.isEmpty)
    }
  }

  /// A loop held between its generation check and its wait must not take over the listener that
  /// replaced its own: its descriptor stays open until it ends, so the number is not reused.
  @Test
  func aLoopHeldBeforeItsWaitDoesNotTakeTheNextListenersFirstClient() async throws {
    let gate = AcceptLoopGate(holding: .socket)
    try await withEndpointServer(beforeAcceptWait: gate.hook) { server, _ in
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      try server.setEnabled(true)
      await waitUntil("the first loop is held") { gate.isHolding }
      try server.setEnabled(false)
      try server.setEnabled(true)
      gate.release()

      // Before any client connects: a loop blocked in `accept` on the next listener's
      // descriptor would stay until a client came.
      await waitUntil("the first loop ends") { server.socketAcceptLoopCount == 1 }
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
    }
  }

  @Test(arguments: [#"["read"]"#, #"["control"]"#])
  func aScopeInTheEarlierSpellingIsRefused(scopes: String) async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read, .control])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":\#(scopes)"#))

      let line = try #require(await client.readLine())
      #expect(try client.object(line)["kind"] as? String == "Status")
      #expect(try client.object(line)["code"] is String)
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func theStreamInTheEarlierSpellingIsRefused() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("Subscription", #","stream":"controllers""#))

      #expect(try await client.readObject()["code"] as? String == "E1003")
    }
  }

  @Test
  func anUngrantedClientIsRefusedAndListedUntilGranted() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "E1002")
      #expect(await client.readLine() == nil)
      let refused = try server.status().refused
      #expect(refused.map(\.id) == [Self.tool.accessID])
      #expect(refused.first?.scopes == [.read])

      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      #expect(try server.status().refused.isEmpty)
    }
  }

  @Test
  func anAdHocClientIsRefusedAndCannotBeGranted() async throws {
    try await withEndpointServer(identity: Self.adHoc) { server, _ in
      try server.setEnabled(true)
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(try server.status().refused.map(\.publisher.kind) == [.adHoc])
      #expect(throws: AccessGrantStoreError.notGrantable(.adHoc)) {
        try server.grant(Self.adHoc, path: "/a.out", scopes: [.read])
      }
    }
  }

  @Test
  func aGrantedClientStreamsControllerEvents() async throws {
    try await withEndpointServer { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.south]))
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      await client.send(clientLine("Subscription", #","stream":"Controllers""#))

      var lines: [String] = []
      for _ in 0..<3 { lines.append(try #require(await client.readLine())) }
      fixture.source.set(devices: [], state: ControllerState(pressed: [.south]))
      lines.append(try #require(await client.readLine()))

      for line in lines {
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      }
      let objects = try lines.map(client.object)
      #expect(
        objects.map { $0["type"] as? String ?? $0["kind"] as? String }
          == ["Welcome", "ADDED", "MODIFIED", "DELETED"]
      )
      #expect(objects[0]["scopes"] as? [String] == ["Read"])
      #expect(objects[0]["version"] as? String == "1.2.3")
      #expect(objects[0]["protocol"] == nil)
      let added = try #require(objects[1]["object"] as? [String: Any])
      #expect(added["apiVersion"] as? String == OpenJoystickDriverAPI.version)
      #expect(added["kind"] as? String == "Controller")
      #expect(added["id"] as? String == token("pad-1"))
      #expect(objects[1]["kind"] == nil)
      let modified = try #require(objects[2]["object"] as? [String: Any])
      #expect(modified["id"] as? String == token("pad-1"))
      #expect((modified["input"] as? [String: Any])?["pressed"] as? [String] == ["South"])
      #expect(modified["output"] == nil)
      let deleted = try #require(objects[3]["object"] as? [String: Any])
      #expect(deleted["id"] as? String == token("pad-1"))
      #expect(deleted["input"] != nil)
      #expect(
        try server.status().connections == [AccessConnection(identity: Self.tool, scopes: [.read])]
      )
    }
  }

  @Test
  func aModifiedUpdateReportsItsSessionTokenToStreamDelivered() async throws {
    let delivered = Locked<[ControllerSessionToken]>([])
    let record: @Sendable (ControllerSessionToken, UInt64) async -> Void = { token, _ in
      delivered.withLock { $0.append(token) }
    }
    try await withEndpointServer(streamDelivered: record) { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.south]))
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient.subscribed(to: server.socketPath)
      var types: [String?] = []
      for _ in 0..<2 {
        types.append(try await client.readObject()["type"] as? String)
      }
      await waitUntil("the feedback is delivered") { delivered.withLock { !$0.isEmpty } }

      #expect(types == ["ADDED", "MODIFIED"])
      #expect(delivered.withLock { $0 } == [.fixture("pad-1")])
    }
  }

  @Test
  func aLateSubscriberFirstReceivesTheConnectedControllers() async throws {
    try await withEndpointServer { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.south]))
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let first = try await EndpointTestClient.subscribed(to: server.socketPath)
      for _ in 0..<2 { _ = try #require(await first.readLine()) }

      let second = try await EndpointTestClient.subscribed(to: server.socketPath)
      let snapshot = try await second.readObject()
      let object = try #require(snapshot["object"] as? [String: Any])
      #expect(snapshot["type"] as? String == "ADDED")
      #expect(object["id"] as? String == token("pad-1"))
      #expect((object["input"] as? [String: Any])?["pressed"] as? [String] == ["South"])
    }
  }

  @Test
  func revokingClosesTheClientsConnections() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient.subscribed(to: server.socketPath)

      let result = try server.revoke(id: Self.tool.accessID, scopes: nil)

      #expect(
        result == AccessRevokeResult(id: Self.tool.accessID, grant: nil, closedConnections: 1)
      )
      #expect(try await client.readObject()["code"] as? String == "E1005")
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func aTokenClientIsWelcomedWithoutAReadableSignature() async throws {
    try await withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(tokenHello(name: "script", token: granted.token, nonce: client.nonce))

      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      #expect(
        try server.status().connections == [
          AccessConnection(
            id: "token:script",
            identifier: "script",
            scopes: [.read],
            transport: .socket
          )
        ]
      )
    }
  }

  @Test
  func aWrongTokenIsRefusedAndListed() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(tokenHello(name: "script", token: "ojd_wrong", nonce: client.nonce))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(await client.readLine() == nil)
      let refused = try server.status().refusedTokens
      #expect(refused.map(\.transport) == [.socket])
      #expect(refused.first?.name == nil)
      #expect(try server.status().refused.isEmpty)
    }
  }

  @Test
  func eachConnectionGetsAFreshChallengeFirst() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      let first = try await EndpointTestClient(path: server.socketPath)
      let second = try await EndpointTestClient(path: server.socketPath)

      // 32 random bytes in unpadded base64url.
      #expect(first.nonce.count == 43)
      #expect(first.nonce.utf8.allSatisfy { $0.isASCIIAlphanumeric || "-_".utf8.contains($0) })
      #expect(first.nonce != second.nonce)
      let line = clientLine("Challenge", #","nonce":"\#(first.nonce)""#)
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    }
  }

  /// A proof is bound to its connection's nonce, so a proof seen once cannot be replayed.
  @Test
  func aProofForAnotherNonceIsRefused() async throws {
    try await withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let other = try await EndpointTestClient(path: server.socketPath)
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(tokenHello(name: "script", token: granted.token, nonce: other.nonce))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(try server.status().refusedTokens.first?.name == nil)
    }
  }

  @Test
  func revokingATokenClosesItsConnections() async throws {
    try await withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(tokenHello(name: "script", token: granted.token, nonce: client.nonce))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")

      let result = try server.revoke(id: "token:script", scopes: nil)

      #expect(result.closedConnections == 1)
      #expect(result.token == nil)
      #expect(try await client.readObject()["code"] as? String == "E1005")
      #expect(try server.status().tokens.isEmpty)
    }
  }

  @Test(arguments: [
    (#"{"apiVersion":"openjoystickdriver.io/v2","kind":"Hello","scopes":["Read"]}"#, "E1009"),
    (#"{"apiVersion":"unsupported.example/v9","kind":"Hello","scopes":["Read"]}"#, "E1009"),
    (#"nonsense"#, "E1003"),
    (clientLine("Hello", #","scopes":[]"#), "E1003"),
    (clientLine("Subscription", #","stream":"Controllers""#), "E1010"),
    (#"{"kind":"Hello","scopes":["Read"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver/v1alpha3","scopes":["Read"]}"#, "E1011"),
    (#"{}"#, "E1011"),
    (#"{"apiVersion":null,"kind":"Hello","scopes":["Read"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver/v1alpha3","kind":null,"scopes":["Read"]}"#, "E1011"),
    (#"{"apiVersion":1,"kind":"Hello","scopes":["Read"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver/v1alpha3","kind":["Hello"],"scopes":["Read"]}"#, "E1011"),
    (#"[1]"#, "E1003"),
    (clientLine("Welcome", #","scopes":["Read"]"#), "E1010"),
    (clientLine("Greeting", #","scopes":["Read"]"#), "E1010"),
    (clientLine("Hello", #","scopes":["Read","Control"]"#), "E1002"),
  ])
  func aBadHelloGetsAnError(hello: String, code: String) async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(hello)

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      let object = try client.object(line)
      #expect(object["code"] as? String == code)
      #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
      #expect(object["kind"] as? String == "Status")
      #expect(object["status"] as? String == "Failure")
      let details = object["details"] as? [String: Any]
      #expect(
        details?["supportedAPIVersions"] as? [String]
          == (["E1009", "E1010", "E1011"].contains(code) ? [OpenJoystickDriverAPI.version] : nil)
      )
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func aClientGrantedControlIsWelcomedWithControl() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.control])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Control"]"#))

      let welcome = try await client.readObject()
      #expect(welcome["kind"] as? String == "Welcome")
      #expect(welcome["apiVersion"] as? String == OpenJoystickDriverAPI.version)
      #expect(welcome["scopes"] as? [String] == ["Control"])
      #expect(
        try server.status().connections == [
          AccessConnection(identity: Self.tool, scopes: [.control])
        ]
      )
    }
  }

  @Test
  func aClientGrantedOnlyReadIsRefusedControl() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Control"]"#))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(await client.readLine() == nil)
      #expect(try server.status().refused.first?.scopes == [.control])
    }
  }

  @Test
  func aSessionWithoutReadCannotSubscribe() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read, .control])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Control"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("Subscription", #","stream":"Controllers""#))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "E1002")
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func aKeepAliveOutsideAFeedIsRefusedWithE1010() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient.subscribed(to: server.socketPath)
      await client.send(clientLine("KeepAlive"))

      #expect(try await client.readObject()["code"] as? String == "E1010")
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func aSecondSubscribeEndsTheConnection() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient.subscribed(to: server.socketPath)
      await client.send(clientLine("Subscription", #","stream":"Controllers""#))

      #expect(try await client.readObject()["code"] as? String == "E1010")
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func theNinthConnectionIsRefused() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      var clients: [EndpointTestClient] = []
      for _ in 0..<EndpointServer.maximumConnections {
        clients.append(try await EndpointTestClient.subscribed(to: server.socketPath))
      }

      let ninth = try await EndpointTestClient(path: server.socketPath)

      #expect(try await ninth.readObject()["code"] as? String == "E1004")
      #expect(await ninth.readLine() == nil)
      _ = clients
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func aNewClientIsServedWhileTheLimitOfIdleClientsIsHeld() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      var clients: [EndpointTestClient] = []
      for _ in 0..<EndpointServer.maximumConnections {
        clients.append(try await EndpointTestClient.subscribed(to: server.socketPath))
      }

      let ninth = try await EndpointTestClient(path: server.socketPath)

      #expect(try await ninth.readObject()["code"] as? String == "E1004")
      // Once a closed client frees its slot, the replacement is served although the other idle
      // clients still hold the limit. The client's 5-second read timeout bounds each wait for a
      // reply; the test sets no other time bound.
      clients.removeLast()
      await waitUntil("the service sees the closed client") {
        server.connectionCount == EndpointServer.maximumConnections - 1
      }
      let replacement = try await EndpointTestClient.subscribed(to: server.socketPath)
      _ = (clients, replacement)
    }
  }

  @Test
  func connectionsAreServedWhileDispatchHasNoFreeThread() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      try await withSaturatedDispatchPool {
        var clients: [EndpointTestClient] = []
        for _ in 0..<EndpointServer.maximumConnections {
          clients.append(try await EndpointTestClient.subscribed(to: server.socketPath))
        }
        let ninth = try await EndpointTestClient(path: server.socketPath)

        #expect(try await ninth.readObject()["code"] as? String == "E1004")
        _ = clients
      }
    }
  }

  @Test
  func aDamagedFileIsReportedAndKeepsTheEndpointClosed() async throws {
    try await withEndpointServer { server, fixture in
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
  func aStaleSocketFileIsReplaced() async throws {
    try await withEndpointServer { server, fixture in
      try fixture.store.save(AccessGrantFile(enabled: true, grants: []))
      let stale = socket(AF_UNIX, SOCK_STREAM, 0)
      var address = try LocalServiceRPCTransport.socketAddress(path: server.socketPath)
      let bound = withUnsafePointer(to: &address) {
        unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          unsafe bind(
            stale,
            $0,
            LocalServiceRPCTransport.socketAddressLength(path: server.socketPath)
          )
        }
      }
      #expect(bound == 0)
      close(stale)

      server.start()

      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["code"] as? String == "E1002")
    }
  }
}
