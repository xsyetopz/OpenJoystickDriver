import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointFeedTests {
  static let tool = EndpointFixture.tool

  @Test
  func frameReachesVirtualGamepad() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      await client.send(
        clientLine("Frame", #","buttons":["South"],"axes":{"LeftStickY":0.5}"#)
      )

      let device = try #require(factory.devices.first)
      #expect(device.profile == .generic)
      await waitUntil("device.sent.contains { $0.buttons.contains(.south) }") {
        device.sent.contains { $0.buttons.contains(.south) }
      }
      let state = try #require(device.sent.last { $0.buttons.contains(.south) })
      #expect(state.axes[.leftStickY] == 0.5)
    }
  }

  @Test
  func hostsRumbleArrivesAsLine() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      device.receive(.setRumble(.off, duration: .milliseconds(200)))
      device.receive(.stopRumble)

      for type in ["SetRumble", "StopRumble"] {
        let line = try #require(await client.readLine())
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
        let object = try client.object(line)
        #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
        #expect(object["kind"] as? String == "RumbleCommand")
        #expect(object["type"] as? String == type)
        #expect(object["durationMilliseconds"] as? Int == (type == "SetRumble" ? 200 : nil))
      }
    }
  }

  @Test
  func closingClientRemovesGamepad() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await feeding(server)
      let device = try #require(factory.devices.first)
      client = nil
      _ = client

      await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingClientWhileQueueIsFullRemovesGamepad() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await feeding(server)
      let device = try #require(factory.devices.first)
      for index in 0..<(VirtualFeedExchangeResult.maximumQueuedFrames + 20) {
        let button = index.isMultiple(of: 2) ? "South" : "East"
        await client?.send(
          clientLine("Frame", #","buttons":["\#(button)"],"holdMilliseconds":60000"#)
        )
      }
      await waitUntil("!device.sent.isEmpty") { !device.sent.isEmpty }
      client = nil
      _ = client

      await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func revokingControlWhileGamepadStartsEndsFeed() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"Generic""#))
      await waitUntil("!factory.devices.isEmpty") { !factory.devices.isEmpty }
      #expect(try server.revoke(id: Self.tool.accessID, scopes: [.control]).closedConnections == 1)

      #expect(try await client.readObject()["code"] as? String == "E1005")
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingClientWhileGamepadStartsEndsFeed() async throws {
    let factory = FakeFeedFactory()
    factory.hangsActivation = true
    let feeds = factory.registry(activationTimeout: 60)
    defer { factory.release() }
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await welcomed(server)
      await client?.send(clientLine("FeedRequest", #","as":"Generic""#))
      await waitUntil("!factory.devices.isEmpty") { !factory.devices.isEmpty }
      client = nil
      _ = client

      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
    }
  }

  /// The client neither reads nor writes, so only the pump sees the closing connection.
  @Test
  func closingConnectionRemovesGamepadWhileReaderAndWriterBlock() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let transport = BlockedTransport()
      defer { transport.release() }
      let connection = EndpointConnection(descriptor: -1, kind: .socket, transport: transport)
      let finished = DispatchSemaphore(value: 0)
      Thread.detachNewThread {
        server.feed(connection, persona: .generic)
        finished.signal()
      }
      await waitUntil("factory.devices.first?.activated != nil") {
        factory.devices.first?.activated != nil
      }
      connection.close(EndpointError(code: .revoked, message: "Revoked."))

      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
      transport.release()
      #expect(await offPool { finished.wait(timeout: .now() + 5) } == .success)
    }
  }

  @Test
  func revokingControlEndsFeed() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      #expect(try server.revoke(id: Self.tool.accessID, scopes: [.control]).closedConnections == 1)

      #expect(try await client.readObject()["code"] as? String == "E1005")
      #expect(await client.readLine() == nil)
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func feedWithoutFrameLinesClosesAfterIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.3, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("Frame", #","buttons":["East"]"#))
      let device = try #require(factory.devices.first)
      await waitUntil("device.sent.contains { $0.buttons.contains(.east) }") {
        device.sent.contains { $0.buttons.contains(.east) }
      }
      await time.waitForSleepers(2)

      // The frame's time passes first; the idle timeout counts from its end.
      time.advance(by: 0.05)
      let frameEnd = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000
      await waitUntil("feeds.lastExchangeTimes.contains(frameEnd)") {
        feeds.lastExchangeTimes.contains(frameEnd)
      }
      await time.waitForSleepers(1)
      time.advance(by: 0.3)
      #expect(try await client.readObject()["code"] as? String == "E1008")
      await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func feedThatKeepsSendingFramesOutlivesIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      // Eight frames 0.2 seconds apart span 1.6 seconds, more than three idle timeouts.
      for index in 0..<8 {
        time.advance(by: 0.2)
        await client.send(clientLine("Frame", #","buttons":["East"]"#))
        // The idle deadline moves only after the device has taken the frame, so the clock
        // advances only once the previous frame is sent.
        await waitUntil("device.sent.count == \(index + 1)") { device.sent.count == index + 1 }
      }

      #expect(feeds.openFeedCount == 1)
      #expect(device.closeCount == 0)
    }
  }

  @Test
  func keepAliveLinesHoldIdleFeedOpenPastIdleTimeout() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("Frame", #","buttons":["East"]"#))
      let device = try #require(factory.devices.first)
      await waitUntil("device.sent.contains { $0.buttons.contains(.east) }") {
        device.sent.contains { $0.buttons.contains(.east) }
      }
      await time.waitForSleepers(2)
      // Let the frame's time pass, so the feed is idle before the first KeepAlive.
      time.advance(by: 0.05)
      let frameEnd = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000
      await waitUntil("feeds.lastExchangeTimes.contains(frameEnd)") {
        feeds.lastExchangeTimes.contains(frameEnd)
      }
      let sentBefore = device.sent.count
      for _ in 0..<8 {
        time.advance(by: 0.2)
        await client.send(clientLine("KeepAlive"))
        // The line has reached the registry once the feed's last exchange is the current time.
        await waitUntil("feeds.lastExchangeTimes.contains(time.now)") {
          feeds.lastExchangeTimes.contains(time.now)
        }
      }

      #expect(feeds.openFeedCount == 1)
      #expect(device.closeCount == 0)
      // A KeepAlive changes nothing: the gamepad shows no new state.
      #expect(device.sent.count == sentBefore)
    }
  }

  @Test
  func idleFeedWithoutKeepAliveLinesClosesWithE1008() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      // Move off time 0 so the KeepAlive's exchange is visible as the current time.
      time.advance(by: 0.0625)
      await client.send(clientLine("KeepAlive"))
      await waitUntil("feeds.lastExchangeTimes.contains(time.now)") {
        feeds.lastExchangeTimes.contains(time.now)
      }

      time.advance(by: 0.5)
      #expect(try await client.readObject()["code"] as? String == "E1008")
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func keepAliveWithAnotherMemberIsRefused() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("KeepAlive", #","buttons":["South"]"#))

      let error = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: error, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(error)["code"] as? String == "E1003")
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
    }
  }

  @Test
  func fifthFeedIsRefused() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      var clients: [EndpointTestClient] = []
      for _ in 0..<VirtualFeedRegistry.maximumFeeds {
        clients.append(try await feeding(server))
      }
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"Generic""#))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "E1007")
      #expect(await client.readLine() == nil)
      #expect(clients.count == VirtualFeedRegistry.maximumFeeds)
    }
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func everyPersonaOpensFeedSession(persona: VirtualHIDProfileID) async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"\#(persona.rawValue)""#))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      let object = try client.object(line)
      #expect(object["kind"] as? String == "FeedSession")
      #expect(object["as"] as? String == persona.rawValue)
      #expect(factory.devices.first?.profile == persona)
    }
  }

  @Test
  func refusedPersonaNamesItAndListsAcceptedOnes() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"quokka""#))

      let object = try await client.readObject()
      let message = try #require(object["message"] as? String)
      #expect(object["code"] as? String == "E1003")
      #expect(message.contains("quokka"))
      for persona in VirtualHIDProfileID.allCases {
        #expect(message.contains(persona.rawValue))
      }
    }
  }

  @Test(arguments: ["NotAPersona", "quokka"])
  func unknownProfileIsInvalid(profile: String) async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("FeedRequest", #","as":"\#(profile)""#))

      #expect(try await client.readObject()["code"] as? String == "E1003")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test(arguments: [
    (clientLine("Subscription", #","stream":"Controllers""#), "E1010"),
    (clientLine("FeedRequest", #","as":"Generic""#), "E1010"),
    (clientLine("Frame", #","buttons":["jump"]"#), "E1003"),
    (clientLine("Frame", #","axes":{"throttle":1}"#), "E1003"),
    (clientLine("Frame", #","holdMilliseconds":60001"#), "E1003"),
    (clientLine("Frame", #","buttons":["South","South"]"#), "E1003"),
    (clientLine("Frame", #","dpad":["DpadUp","DpadUp"]"#), "E1003"),
    (clientLine("Frame", #","dpad":["notAName"]"#), "E1003"),
    (clientLine("Frame", #","buttons":["South"],"turbo":true"#), "E1003"),
    (#"{"buttons":["South"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver.io/v2","kind":"Frame","buttons":["South"]}"#, "E1009"),
    (#"{"kind":"Frame","buttons":["South"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver/v1alpha3","buttons":["South"]}"#, "E1011"),
    (#"{"apiVersion":null,"kind":"Frame","buttons":["South"]}"#, "E1011"),
    (#"{"apiVersion":"openjoystickdriver/v1alpha3","kind":null,"buttons":["South"]}"#, "E1011"),
    (#"{"apiVersion":2,"kind":"Frame","buttons":["South"]}"#, "E1011"),
    (clientLine("Greeting", ""), "E1010"),
    ("nonsense", "E1003"),
  ])
  func lineThatIsNotFrameEndsFeed(line: String, code: String) async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(line)

      let error = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: error, against: "endpoint.schema.json").isEmpty)
      let object = try client.object(error)
      #expect(object["code"] as? String == code)
      let details = object["details"] as? [String: Any]
      #expect(
        details?["supportedAPIVersions"] as? [String]
          == (code == "E1003" ? nil : [OpenJoystickDriverAPI.version])
      )
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func sessionWithoutControlCannotFeed() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient(path: server.socketPath)
      await client.send(clientLine("Hello", #","scopes":["Read"]"#))
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("FeedRequest", #","as":"Generic""#))

      #expect(try await client.readObject()["code"] as? String == "E1002")
      #expect(factory.devices.isEmpty)
    }
  }

  @Test
  func originlessTokenFeedsOverWebSocket() async throws {
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
          scopes: ["Control"]
        )
      )
      #expect(try await client.readObject()["kind"] as? String == "Welcome")
      await client.send(clientLine("FeedRequest", #","as":"SDLCompatible""#))
      let feeding = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: feeding, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(feeding)["as"] as? String == "SDLCompatible")
      await client.send(clientLine("Frame", #","dpad":["DpadUp"]"#))

      let device = try #require(factory.devices.first)
      await waitUntil("device.sent.contains { $0.dpad.contains(.up) }") {
        device.sent.contains { $0.dpad.contains(.up) }
      }
    }
  }

  // MARK: - Helpers

  /// A signed client granted `control`, welcomed with it.
  func welcomed(_ server: EndpointServer) async throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(Self.tool, path: "/Tool", scopes: [.control])
    let client = try await EndpointTestClient(path: server.socketPath)
    await client.send(clientLine("Hello", #","scopes":["Control"]"#))
    #expect(try await client.readObject()["kind"] as? String == "Welcome")
    return client
  }

  /// A welcomed client that started a `Generic` feed and read `feeding`.
  func feeding(_ server: EndpointServer) async throws -> EndpointTestClient {
    let client = try await welcomed(server)
    await client.send(clientLine("FeedRequest", #","as":"Generic""#))
    let line = try #require(await client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    let feeding = try client.object(line)
    #expect(feeding["kind"] as? String == "FeedSession")
    #expect(feeding["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(feeding["as"] as? String == "Generic")
    return client
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

  func writeMessage(_: Data) -> Bool {
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
