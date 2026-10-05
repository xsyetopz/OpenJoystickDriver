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
  func closingTheClientWhileTheQueueIsFullRemovesTheGamepad() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try feeding(server)
      let device = try #require(factory.devices.first)
      for index in 0..<(VirtualFeedExchangeResult.maximumQueuedFrames + 20) {
        let button = index.isMultiple(of: 2) ? "south" : "east"
        client?.send(#"{"buttons":["\#(button)"],"holdMilliseconds":60000}"#)
      }
      try Self.wait { !device.sent.isEmpty }
      client = nil
      _ = client

      try Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func revokingControlWhileTheGamepadStartsEndsTheFeed() throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try welcomed(server)
      client.send(#"{"type":"feed","as":"hid-generic"}"#)
      try Self.wait { !factory.devices.isEmpty }
      try server.revoke(id: Self.tool.accessID, scopes: [.control])

      #expect(try client.readObject()["code"] as? String == "E1006")
      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingTheClientWhileTheGamepadStartsEndsTheFeed() throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try welcomed(server)
      client?.send(#"{"type":"feed","as":"hid-generic"}"#)
      try Self.wait { !factory.devices.isEmpty }
      client = nil
      _ = client

      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  /// The client neither reads nor writes, so only the pump sees the closing connection.
  @Test
  func aClosingConnectionRemovesTheGamepadWhileTheReaderAndWriterBlock() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      let transport = BlockedTransport()
      defer { transport.release() }
      let connection = EndpointConnection(descriptor: -1, kind: .socket, transport: transport)
      let finished = DispatchSemaphore(value: 0)
      Thread.detachNewThread {
        server.feed(connection, profile: "hid-generic")
        finished.signal()
      }
      try Self.wait { factory.devices.first?.activated != nil }
      connection.close(EndpointError(code: .revoked, message: "Revoked."))

      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
      transport.release()
      #expect(finished.wait(timeout: .now() + 5) == .success)
    }
  }

  @Test
  func revokingControlEndsTheFeed() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      try server.revoke(id: Self.tool.accessID, scopes: [.control])

      #expect(try client.readObject()["code"] as? String == "E1006")
      #expect(client.readLine() == nil)
      try Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aFeedWithoutFrameLinesClosesAfterTheIdleTimeout() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 0.3)
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      client.send(#"{"buttons":["east"]}"#)
      let device = try #require(factory.devices.first)
      try Self.wait { device.sent.contains { $0.buttons.contains(.east) } }

      #expect(try client.readObject()["code"] as? String == "E1009")
      try Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aFeedThatKeepsSendingFramesOutlivesTheIdleTimeout() throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 0.5)
    try withEndpointServer(feeds: feeds) { server, _ in
      let client = try feeding(server)
      for _ in 0..<8 {
        client.send(#"{"buttons":["east"]}"#)
        usleep(150_000)
      }

      #expect(feeds.openFeedCount == 1)
      #expect(factory.devices.first?.closeCount == 0)
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
      #expect(try client.object(line)["code"] as? String == "E1008")
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

      #expect(try client.readObject()["code"] as? String == "E1004")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test(arguments: [
    #"{"type":"subscribe","stream":"controllers"}"#,
    #"{"type":"feed","as":"hid-generic"}"#,
    #"{"buttons":["jump"]}"#,
    #"{"axes":{"throttle":1}}"#,
    #"{"holdMilliseconds":60001}"#,
    #"{"buttons":["south","south"]}"#,
    #"{"dpad":["up","up"]}"#,
    #"{"buttons":["south"],"turbo":true}"#,
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
      #expect(try client.object(error)["code"] as? String == "E1004")
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

      #expect(try client.readObject()["code"] as? String == "E1002")
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

/// A transport whose reads and writes block until `release`; then reads end and writes fail.
private final class BlockedTransport: EndpointTransport, @unchecked Sendable {
  private let released = DispatchSemaphore(value: 0)

  func release() { released.signal() }

  func readMessage() -> EndpointReadResult {
    waitForRelease()
    return .end
  }

  func writeMessage(_ data: Data) -> Bool {
    waitForRelease()
    return false
  }

  func writeClose() {}

  /// Passes the release on, so every blocked call returns.
  private func waitForRelease() {
    released.wait()
    released.signal()
  }
}
