import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointFeedTests {
  private static let tool = EndpointFixture.tool

  @Test
  func aFrameReachesTheVirtualGamepad() throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try feeding(server)
      client.send(#"{"buttons":["south"],"axes":{"left_stick_y":0.5}}"#)

      let device = try #require(factory.devices.first)
      #expect(device.profile == .generic)
      try Self.wait { device.sent.contains { $0.buttons.contains(.south) } }
      let state = try #require(device.sent.last { $0.buttons.contains(.south) })
      #expect(state.axes[.leftStickY] == -0.5)
    }
  }

  @Test
  func theHostsRumbleArrivesAsALine() throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try feeding(server)
      let device = try #require(factory.devices.first)
      device.receive(.setRumble(.off, duration: .milliseconds(200)))
      device.receive(.stopRumble)

      for type in ["set-rumble", "stop-rumble"] {
        let line = try #require(client.readLine())
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
        #expect(try client.object(line)["type"] as? String == type)
      }
    }
  }

  @Test
  func closingTheClientRemovesTheGamepad() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try feeding(server)
      let device = try #require(factory.devices.first)
      client = nil
      _ = client

      try Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func revokingControlEndsTheFeed() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      try server.revoke(id: Self.tool.accessID, scopes: [.control])

      #expect(try client.readObject()["code"] as? String == "revoked")
      #expect(client.readLine() == nil)
      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aFeedOutlivesTheIdleTimeoutWithoutClientLines() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 0.2)
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      usleep(600_000)

      #expect(feeds.openFeedCount == 1)
      #expect(factory.devices.first?.closeCount == 0)
      client.send(#"{"buttons":["east"]}"#)
      let device = try #require(factory.devices.first)
      try Self.wait { device.sent.contains { $0.buttons.contains(.east) } }
    }
  }

  @Test
  func aFifthFeedIsRefused() throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      let clients = try (0..<VirtualFeedRegistry.maximumFeeds).map { _ in try feeding(server) }
      let client = try welcomed(server)
      client.send(#"{"type":"feed","as":"hid-generic"}"#)

      let line = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "too-many-feeds")
      #expect(client.readLine() == nil)
      #expect(clients.count == VirtualFeedRegistry.maximumFeeds)
    }
  }

  @Test(arguments: ["hid-unknown", "Hid-Generic"])
  func anUnknownProfileIsInvalid(profile: String) throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try welcomed(server)
      client.send(#"{"type":"feed","as":"\#(profile)"}"#)

      #expect(try client.readObject()["code"] as? String == "invalid-message")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test(arguments: [
    #"{"type":"subscribe","stream":"controllers"}"#,
    #"{"type":"feed","as":"hid-generic"}"#,
    #"{"buttons":["jump"]}"#,
    #"{"axes":{"throttle":1}}"#,
    #"{"holdMilliseconds":60001}"#,
    "nonsense",
  ])
  func aLineThatIsNotAFrameEndsTheFeed(line: String) throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      client.send(line)

      let error = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: error, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(error)["code"] as? String == "invalid-message")
      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aSessionWithoutControlCannotFeed() throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try EndpointTestClient(path: server.socketPath)
      client.send(#"{"type":"hello","protocol":1,"scopes":["read"]}"#)
      #expect(try client.readObject()["type"] as? String == "welcome")
      client.send(#"{"type":"feed","as":"hid-generic"}"#)

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test
  func anOriginlessTokenFeedsOverTheWebSocket() throws {
    let factory = FakeFeedFactory()
    try withEndpointServer(feeds: factory.registry()) { server, _ in
      try server.setWebEnabled(true, port: nil)
      let pad = try server.grantToken(name: "pad", origins: [], scopes: [.control])
      let port = try #require(server.status().web.port)
      let client = try EndpointWebTestClient(port: port)
      let response = client.request(
        "/endpoint",
        headers: EndpointWebTestClient.upgradeHeaders(port: port, origin: nil)
      )
      #expect(response?.status == 101)
      try client.readChallenge()
      client.send(
        tokenHello(
          name: "pad",
          token: pad.token,
          nonce: client.nonce,
          port: String(port),
          scopes: ["control"]
        )
      )
      #expect(try client.readObject()["type"] as? String == "welcome")
      client.send(#"{"type":"feed","as":"hid-xbox-one-s-bt"}"#)
      let feeding = try #require(client.readLine())
      #expect(try JSONSchemaFiles.issues(in: feeding, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(feeding)["as"] as? String == "hid-xbox-one-s-bt")
      client.send(#"{"dpad":["up"]}"#)

      let device = try #require(factory.devices.first)
      try Self.wait { device.sent.contains { $0.dpad.contains(.up) } }
    }
  }

  // MARK: - Helpers

  /// A signed client granted `control`, welcomed with it.
  private func welcomed(_ server: EndpointServer) throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(Self.tool, path: "/Tool", scopes: [.control])
    let client = try EndpointTestClient(path: server.socketPath)
    client.send(#"{"type":"hello","protocol":1,"scopes":["control"]}"#)
    #expect(try client.readObject()["type"] as? String == "welcome")
    return client
  }

  /// A welcomed client that started a `hid-generic` feed and read `feeding`.
  private func feeding(_ server: EndpointServer) throws -> EndpointTestClient {
    let client = try welcomed(server)
    client.send(#"{"type":"feed","as":"hid-generic"}"#)
    let line = try #require(client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    let feeding = try client.object(line)
    #expect(feeding["type"] as? String == "feeding")
    #expect(feeding["as"] as? String == "hid-generic")
    return client
  }

  /// Waits up to 5 seconds until `condition` holds.
  private static func wait(until condition: () -> Bool) throws {
    let deadline = Date() + 5
    while !condition() {
      guard Date() < deadline else { throw POSIXError(.ETIMEDOUT) }
      usleep(2_000)
    }
  }
}
