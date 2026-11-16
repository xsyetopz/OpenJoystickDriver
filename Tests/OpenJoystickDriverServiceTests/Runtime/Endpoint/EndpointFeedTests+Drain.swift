import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension EndpointFeedTests {
  @Test
  func drainedComesOnlyAfterLastFramesHoldEvenWhenSendIsSlow() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      // The first send takes 0.5 seconds on the clock before it returns.
      device.duringSend = { sent in if sent == 0 { time.advance(by: 0.5) } }
      let minimum = Double(VirtualFeedExchangeResult.minimumFrameMilliseconds) / 1000

      await client.send(clientLine("Frame", #","buttons":["South"],"holdMilliseconds":100"#))
      await client.send(clientLine("Frame", #","buttons":["East"]"#))
      await client.send(clientLine("Drain"))
      // The first frame ends at 0.5 + 0.1; the second is sent then and ends a minimum later.
      let lastEnd = 0.6 + minimum
      let arrival = Task { () -> (line: String?, time: TimeInterval, sent: Int) in
        let line = await client.readLine()
        return (line, time.now, device.sent.count)
      }
      await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
      await time.waitForSleeper(due: 0.6)
      time.advance(by: 0.1)
      await waitUntil("device.sent.count == 2") { device.sent.count == 2 }
      await time.waitForSleeper(due: lastEnd)
      time.advance(by: minimum)

      let result = await arrival.value
      let line = try #require(result.line)
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["kind"] as? String == "Drained")
      #expect(result.time >= lastEnd - 1e-9)
      #expect(result.sent == 2)
      #expect(device.closeCount == 0)
    }
  }

  @Test
  func drainedComesAtOnceWhenNoFrameWaits() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("Drain"))

      #expect(try await client.readObject()["kind"] as? String == "Drained")
      await client.send(clientLine("Drain"))
      #expect(try await client.readObject()["kind"] as? String == "Drained")
    }
  }

  @Test
  func drainBeforeFeedSessionGetsE1010() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("Drain"))

      let line = try #require(await client.readLine())
      #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      #expect(try client.object(line)["code"] as? String == "E1010")
      #expect(await client.readLine() == nil)
      #expect(factory.devices.isEmpty)
    }
  }

  @Test
  func drainOnSubscriptionGetsE1010() async throws {
    try await withEndpointServer { server, _ in
      try server.setEnabled(true)
      try server.grant(Self.tool, path: "/Tool", scopes: [.read])
      let client = try await EndpointTestClient.subscribed(to: server.socketPath)
      await client.send(clientLine("Drain"))

      #expect(try await client.readObject()["code"] as? String == "E1010")
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func drainWithAnotherMemberIsRefused() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(feeds: factory.registry()) { server, _ in
      let client = try await feeding(server)
      await client.send(clientLine("Drain", #","buttons":["South"]"#))

      #expect(try await client.readObject()["code"] as? String == "E1003")
      await waitUntil("factory.devices.first?.closeCount == 1") {
        factory.devices.first?.closeCount == 1
      }
    }
  }

  @Test
  func pendingDrainKeepsFeedOpenPastIdleTimeoutUntilFramesHavePlayed() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      await client.send(clientLine("Frame", #","buttons":["South"],"holdMilliseconds":3000"#))
      await client.send(clientLine("Drain"))
      await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
      await time.waitForSleeper(due: 3)

      // The client sends nothing for six idle timeouts while the frame plays.
      for _ in 0..<6 {
        time.advance(by: 0.45)
        #expect(feeds.openFeedCount == 1)
      }
      time.advance(by: 0.3)

      #expect(try await client.readObject()["kind"] as? String == "Drained")
      #expect(feeds.openFeedCount == 1)
      #expect(device.closeCount == 0)
    }
  }

  @Test
  func afterDrainedClientThatSendsNothingIsClosedWithE1008() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      let client = try await feeding(server)
      let device = try #require(factory.devices.first)
      await client.send(clientLine("Frame", #","buttons":["South"],"holdMilliseconds":1000"#))
      await client.send(clientLine("Drain"))
      await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
      await time.waitForSleeper(due: 1)
      time.advance(by: 1)
      #expect(try await client.readObject()["kind"] as? String == "Drained")

      // The idle time counts from the end of the last frame's time.
      time.advance(by: 0.5)
      #expect(try await client.readObject()["code"] as? String == "E1008")
      await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }

  @Test
  func closingClientWhileDrainWaitsRemovesGamepad() async throws {
    let factory = FakeFeedFactory()
    let time = ManualVirtualFeedClock()
    let feeds = factory.registry(idleTimeout: 0.5, clock: time.clock)
    try await withEndpointServer(feeds: feeds) { server, _ in
      var client: EndpointTestClient? = try await feeding(server)
      let device = try #require(factory.devices.first)
      await client?.send(clientLine("Frame", #","buttons":["South"],"holdMilliseconds":60000"#))
      await client?.send(clientLine("Drain"))
      await waitUntil("device.sent.count == 1") { device.sent.count == 1 }
      client = nil
      _ = client

      await waitUntil("device.closeCount == 1") { device.closeCount == 1 }
      #expect(feeds.openFeedCount == 0)
    }
  }
}
