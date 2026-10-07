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
  func aFrameReachesTheVirtualGamepad() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      await client.send(
        clientLine("Frame", #","buttons":["south"],"axes":{"left_stick_y":0.5}"#)
      )

      let device = try #require(factory.devices.first)
      #expect(device.profile == .generic)
      try await Self.wait { device.sent.contains { $0.buttons.contains(.south) } }
      let state = try #require(device.sent.last { $0.buttons.contains(.south) })
      #expect(state.axes[.leftStickY] == -0.5)
    }
  }

  @Test
  func theHostsRumbleArrivesAsALine() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      device.receive(.setRumble(.off, duration: .milliseconds(200)))
      device.receive(.stopRumble)

      for type in ["setRumble", "stopRumble"] {
        let line = try #require(await client.readLine())
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
        let object = try client.object(line)
        #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
        #expect(object["kind"] as? String == "RumbleCommand")
        #expect(object["type"] as? String == type)
        #expect(object["durationMilliseconds"] as? Int == (type == "setRumble" ? 200 : nil))
      }
    }
  }

  @Test
  func closingTheClientRemovesTheGamepad() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await feeding(server)
      let device = try #require(factory.devices.first)
      client = nil
      _ = client

      try await Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingTheClientWhileTheQueueIsFullRemovesTheGamepad() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await feeding(server)
      let device = try #require(factory.devices.first)
      for index in 0..<(VirtualFeedExchangeResult.maximumQueuedFrames + 20) {
        let button = index.isMultiple(of: 2) ? "south" : "east"
        await client?.send(
          clientLine("Frame", #","buttons":["\#(button)"],"holdMilliseconds":60000"#)
        )
      }
      try await Self.wait { !device.sent.isEmpty }
      client = nil
      _ = client

      try await Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func revokingControlWhileTheGamepadStartsEndsTheFeed() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"hid-generic""#))
      try await Self.wait { !factory.devices.isEmpty }
      #expect(try server.revoke(id: Self.tool.accessID, scopes: [.control]).closedConnections == 1)

      #expect(try await client.readObject()["code"] as? String == "E1006")
      try await Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingTheClientWhileTheGamepadStartsEndsTheFeed() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await welcomed(server)
      await client?.send(clientLine("FeedRequest", #","as":"hid-generic""#))
      try await Self.wait { !factory.devices.isEmpty }
      client = nil
      _ = client

      try await Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  /// The client neither reads nor writes, so only the pump sees the closing connection.
  @Test
  func aClosingConnectionRemovesTheGamepadWhileTheReaderAndWriterBlock() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let transport = BlockedTransport()
      defer { transport.release() }
      let connection = EndpointConnection(descriptor: -1, kind: .socket, transport: transport)
      let finished = DispatchSemaphore(value: 0)
      Thread.detachNewThread {
        server.feed(connection, profile: "hid-generic")
        finished.signal()
      }
      try await Self.wait { factory.devices.first?.activated != nil }
      connection.close(EndpointError(code: .revoked, message: "Revoked."))

      try await Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
      transport.release()
      #expect(await offPool { finished.wait(timeout: .now() + 5) } == .success)
    }
  }

  @Test
  func revokingControlEndsTheFeed() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      #expect(try server.revoke(id: Self.tool.accessID, scopes: [.control]).closedConnections == 1)

      #expect(try await client.readObject()["code"] as? String == "E1006")
      #expect(await client.readLine() == nil)
      try await Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aFeedWithoutFrameLinesClosesAfterTheIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 0.3)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("Frame", #","buttons":["east"]"#))
      let device = try #require(factory.devices.first)
      try await Self.wait { device.sent.contains { $0.buttons.contains(.east) } }

      #expect(try await client.readObject()["code"] as? String == "E1009")
      try await Self.wait { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aFeedThatKeepsSendingFramesOutlivesTheIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 0.5)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      for _ in 0..<8 {
        await client.send(clientLine("Frame", #","buttons":["east"]"#))
        try await Task.sleep(nanoseconds: 150_000_000)
      }

      #expect(feeds.openFeedCount == 1)
      #expect(factory.devices.first?.closeCount == 0)
    }
  }

  @Test
  func aFifthFeedIsRefused() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      var clients: [EndpointTestClient] = []
      for _ in 0..<VirtualFeedRegistry.maximumFeeds {
        clients.append(try await feeding(server))
      }
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"hid-generic""#))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "E1008")
      #expect(await client.readLine() == nil)
      #expect(clients.count == VirtualFeedRegistry.maximumFeeds)
    }
  }

  @Test(arguments: ["hid-unknown", "Hid-Generic"])
  func anUnknownProfileIsInvalid(profile: String) async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"\#(profile)""#))

      #expect(try await client.readObject()["code"] as? String == "E1004")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test(arguments: [
    clientLine("Subscription", #","stream":"controllers""#),
    clientLine("FeedRequest", #","as":"hid-generic""#),
    clientLine("Frame", #","buttons":["jump"]"#),
    clientLine("Frame", #","axes":{"throttle":1}"#),
    clientLine("Frame", #","holdMilliseconds":60001"#),
    clientLine("Frame", #","buttons":["south","south"]"#),
    clientLine("Frame", #","dpad":["up","up"]"#),
    clientLine("Frame", #","buttons":["south"],"turbo":true"#),
    #"{"buttons":["south"]}"#,
    #"{"apiVersion":"openjoystickdriver.io/v2","kind":"Frame","buttons":["south"]}"#,
    #"{"kind":"Frame","buttons":["south"]}"#,
    "nonsense",
  ])
  func aLineThatIsNotAFrameEndsTheFeed(line: String) async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(line)

      let error = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: error, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(error)["code"] as? String == "E1004")
      try await Self.wait { factory.devices.first?.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func aSessionWithoutControlCannotFeed() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("FeedRequest", #","as":"hid-generic""#))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test
  func anOriginlessTokenFeedsOverTheWebSocket() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      try server.setWebEnabled(true, port: nil)
      let pad = try server.grantToken(name: "pad", origins: [], scopes: [.control])
      let port = try #require(server.status().web.port)
      let client = try await EndpointWebTestClient(port: port)
      let response = await client.request(
        "/endpoint",
        headers: EndpointWebTestClient.upgradeHeaders(port: port, origin: nil)
      )
      #expect(response?.status == 101)
      try await client.readChallenge()
      await client.send(
        tokenHello(
          name: "pad",
          token: pad.token,
          nonce: client.nonce,
          port: String(port),
          scopes: ["control"]
        )
      )
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("FeedRequest", #","as":"hid-xbox-one-s-bt""#))
      let feeding = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: feeding, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(feeding)["as"] as? String == "hid-xbox-one-s-bt")
      await client.send(clientLine("Frame", #","dpad":["up"]"#))

      let device = try #require(factory.devices.first)
      try await Self.wait { device.sent.contains { $0.dpad.contains(.up) } }
    }
  }

  // MARK: - Helpers

  /// A signed client granted `control`, welcomed with it.
  private func welcomed(_ server: EndpointServer) async throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(Self.tool, path: "/Tool", scopes: [.control])
    let client = try await EndpointTestClient(path: server.socketPath)
    await client.send(clientLine("Hello", #","scopes":["control"]"#))
    #expect(try await client.readObject()["kind"] as? String == "Welcome")
    return client
  }

  /// A welcomed client that started a `hid-generic` feed and read `feeding`.
  private func feeding(_ server: EndpointServer) async throws -> EndpointTestClient {
    let client = try await welcomed(server)
    await client.send(clientLine("FeedRequest", #","as":"hid-generic""#))
    let line = try #require(await client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    let feeding = try client.object(line)
    #expect(feeding["kind"] as? String == "FeedSession")
    #expect(feeding["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(feeding["as"] as? String == "hid-generic")
    return client
  }

  /// Waits up to 5 seconds until `condition` holds, without holding a thread.
  private static func wait(until condition: () -> Bool) async throws {
    let deadline = Date() + 5
    while !condition() {
      guard Date() < deadline else { throw POSIXError(.ETIMEDOUT) }
      try await Task.sleep(nanoseconds: 2_000_000)
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
