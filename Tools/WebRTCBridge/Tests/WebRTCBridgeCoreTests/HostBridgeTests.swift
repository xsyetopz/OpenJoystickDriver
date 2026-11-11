import Foundation
import Testing

@testable import BridgeCore
@testable import WebRTCBridgeCore

/// A data channel in memory: the test plays the peer.
private final class FakeChannel: PeerChannel, @unchecked Sendable {
  /// Guards `handler` and `messages`.
  private let lock = NSLock()
  /// The handler that the bridge sets.
  private var handler: (@Sendable (Data) -> Void)?
  /// The messages that the bridge sent.
  private var messages: [Data] = []

  /// The handler for the messages of the peer, read and written under the lock.
  var onMessage: (@Sendable (Data) -> Void)? {
    get { lock.withLock { handler } }
    set { lock.withLock { handler = newValue } }
  }

  /// The messages that the bridge sent to the peer.
  var sent: [Data] { lock.withLock { messages } }

  /// Records the message and accepts it.
  func send(_ data: Data) -> Bool {
    lock.withLock { messages.append(data) }
    return true
  }

  /// Delivers the text to the bridge as a message of the peer.
  func peerSends(_ text: String) { onMessage?(Data(text.utf8)) }
}

extension ListeningSocketSuites {
  /// Checks that ``HostBridge`` passes valid peer frames to the endpoint and rumble to the peer.
  final class HostBridgeTests {
    /// The `apiVersion` member that every message carries, as JSON text.
    private static let header = #""apiVersion":"openjoystickdriver/v1alpha3""#

    /// Serves one connection on the endpoint and starts a bridge on a fake channel.
    private func started(
      _ endpoint: FakeEndpoint
    ) throws -> (bridge: HostBridge, channel: FakeChannel) {
      endpoint.serve(connections: 1)
      let channel = FakeChannel()
      let bridge = HostBridge(link: channel)
      try bridge.start(
        EndpointCredentials(
          socketPath: endpoint.path,
          token: FakeEndpoint.token,
          tokenName: FakeEndpoint.tokenName
        )
      )
      return (bridge, channel)
    }

    /// Invalid peer messages produce no write to the endpoint.
    @Test
    func anInvalidPeerMessageProducesNoEndpointWrite() async throws {
      let endpoint = try FakeEndpoint()
      let (bridge, channel) = try started(endpoint)
      channel.peerSends("not json")
      channel.peerSends(#"{\#(Self.header),"kind":"Frame","holdMilliseconds":60001}"#)
      channel.peerSends(#"{\#(Self.header),"kind":"Frame","extra":true}"#)
      channel.peerSends(#"{\#(Self.header),"kind":"KeepAlive"}"#)
      try await Task.sleep(nanoseconds: 300_000_000)

      #expect(endpoint.snapshot().frames.isEmpty)
      bridge.stop()
    }

    /// One frame is sent once, and an idle feed gets only `KeepAlive` lines.
    @Test
    func aFrameIsSentOnceAndAnIdleFeedGetsOnlyKeepAlive() async throws {
      let endpoint = try FakeEndpoint()
      let (bridge, channel) = try started(endpoint)
      channel.peerSends(#"{\#(Self.header),"kind":"Frame","buttons":["South"]}"#)
      try await Task.sleep(nanoseconds: 1_700_000_000)

      let frames = endpoint.snapshot().frames
      #expect(frames.count == 1)
      #expect((frames.first?["buttons"] as? [String]) == ["South"])
      #expect(endpoint.keepAliveCount() >= 2)
      bridge.stop()
    }

    /// Only a valid, short `RumbleCommand` of the endpoint is sent to the peer.
    @Test
    func onlyAValidRumbleCommandOfTheEndpointGoesToThePeer() async throws {
      let rumble: [String: Any] = [
        "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "StopRumble",
      ]
      let oversize: [String: Any] = [
        "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "StopRumble",
        "padding": String(repeating: "x", count: PeerMessage.maximumBytes),
      ]
      let endpoint = try FakeEndpoint(
        rumble: rumble,
        feedLines: [
          ["apiVersion": endpointAPIVersion, "kind": "Status", "status": "Success"],
          ["apiVersion": endpointAPIVersion, "kind": "Frame"],
          oversize,
        ]
      )
      let (bridge, channel) = try started(endpoint)
      channel.peerSends(#"{\#(Self.header),"kind":"Frame","buttons":["South"]}"#)
      try await Task.sleep(nanoseconds: 500_000_000)

      let sent = channel.sent.compactMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
      }
      #expect(sent.count == 1)
      #expect((sent.first?["kind"] as? String) == "RumbleCommand")
      #expect((sent.first?["type"] as? String) == "StopRumble")
      bridge.stop()
    }
  }
}
