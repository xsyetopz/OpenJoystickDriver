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
    try withEndpointServer { server, _ in
      server.start()
      #expect(!FileManager.default.fileExists(atPath: server.socketPath))
      let status = try server.status()
      #expect(status.enabled == false)
    }
  }

  @Test
  func disablingRemovesTheSocketAndClosesEveryConnection() throws {
    try withEndpointServer { server, _ in
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
    try withEndpointServer { server, _ in
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
    try withEndpointServer(identity: Self.adHoc) { server, _ in
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
    try withEndpointServer { server, fixture in
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
    try withEndpointServer { server, fixture in
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
    try withEndpointServer { server, _ in
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

  @Test
  func aTokenClientIsWelcomedWithoutAReadableSignature() throws {
    try withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(tokenHello(name: "script", token: granted.token, nonce: client.nonce))

      #expect(try client.readObject()["type"] as? String == "welcome")
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
  func aWrongTokenIsRefusedAndListed() throws {
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(tokenHello(name: "script", token: "ojd_wrong", nonce: client.nonce))

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
      let refused = try server.status().refusedTokens
      #expect(refused.map(\.transport) == [.socket])
      #expect(refused.first?.name == nil)
      #expect(try server.status().refused.isEmpty)
    }
  }

  @Test
  func eachConnectionGetsAFreshChallengeFirst() throws {
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      let first = try EndpointTestClient(path: server.socketPath)
      let second = try EndpointTestClient(path: server.socketPath)

      // 32 random bytes in unpadded base64url.
      #expect(first.nonce.count == 43)
      #expect(first.nonce.utf8.allSatisfy { $0.isASCIIAlphanumeric || "-_".utf8.contains($0) })
      #expect(first.nonce != second.nonce)
      let line = #"{"type":"challenge","nonce":"\#(first.nonce)"}"#
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    }
  }

  /// A proof is bound to its connection's nonce, so a proof seen once cannot be replayed.
  @Test
  func aProofForAnotherNonceIsRefused() throws {
    try withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let other = try EndpointTestClient(path: server.socketPath)
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(tokenHello(name: "script", token: granted.token, nonce: other.nonce))

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(try server.status().refusedTokens.first?.name == nil)
    }
  }

  @Test
  func revokingATokenClosesItsConnections() throws {
    try withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(tokenHello(name: "script", token: granted.token, nonce: client.nonce))
      #expect(try client.readObject()["type"] as? String == "welcome")

      let result = try server.revoke(id: "token:script", scopes: nil)

      #expect(result.closedConnections == 1)
      #expect(result.token == nil)
      #expect(try client.readObject()["code"] as? String == "revoked")
      #expect(try server.status().tokens.isEmpty)
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
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
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
  func aClientGrantedControlIsWelcomedWithControl() throws {
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.control])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["control"]}"#)

      let welcome = try client.readObject()
      #expect(welcome["type"] as? String == "welcome")
      #expect(welcome["scopes"] as? [String] == ["control"])
      #expect(
        try server.status().connections == [
          AccessConnection(identity: Self.tool, scopes: [.control])
        ]
      )
    }
  }

  @Test
  func aClientGrantedOnlyReadIsRefusedControl() throws {
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["control"]}"#)

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
      #expect(try server.status().refused.first?.scopes == [.control])
    }
  }

  @Test
  func aSessionWithoutReadCannotSubscribe() throws {
    try withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read, .control])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["control"]}"#)
      #expect(try client.readObject()["type"] as? String == "welcome")
      client.send(#"{"type":"subscribe","stream":"controllers"}"#)

      let line = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
    }
  }

  @Test
  func aSecondSubscribeEndsTheConnection() throws {
    try withEndpointServer { server, _ in
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
    try withEndpointServer { server, _ in
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
    try withEndpointServer { server, fixture in
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
    try withEndpointServer { server, fixture in
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
}
