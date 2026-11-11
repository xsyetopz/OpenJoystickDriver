import BridgeCore
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// A data channel in memory: the test plays the peer.
private final class FakePeerChannel: PeerChannel, @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (Data) -> Void)?

  var onMessage: (@Sendable (Data) -> Void)? {
    get { lock.withLock { handler } }
    set { lock.withLock { handler = newValue } }
  }

  func send(_: Data) -> Bool { true }

  func peerSends(_ text: String) { onMessage?(Data(text.utf8)) }
}

/// Runs the bridge's host role (`BridgeCore`, the part of `Tools/WebRTCBridge` that has no WebRTC
/// dependency) against a real ``EndpointServer`` on a Unix socket.
@Suite(.serialized)
struct EndpointBridgeTests {
  private static let header = #""apiVersion":"\#(OpenJoystickDriverAPI.version)""#

  @Test
  func aGrantedFeedReachesTheVirtualDeviceAndStaysOpenOnKeepAlive() async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry(idleTimeout: 1)
    try await withEndpointServer(identity: nil, feeds: feeds) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "bridge", origins: [], scopes: [.control])
      let channel = FakePeerChannel()
      let bridge = HostBridge(link: channel)
      defer { bridge.stop() }

      let failure = await Self.start(bridge, server: server, token: granted.token)
      #expect(failure == nil)
      channel.peerSends(#"{\#(Self.header),"kind":"Frame","buttons":["South"]}"#)

      let device = try #require(factory.devices.first)
      #expect(device.profile == .generic)
      await waitUntil("device.sent.contains { $0.buttons.contains(.south) }") {
        device.sent.contains { $0.buttons.contains(.south) }
      }
      let sentBefore = device.sent.count
      // Without a KeepAlive the endpoint closes the feed after 1 second; the bridge sends one
      // every 0.5 second while the peer sends no frame.
      try await Task.sleep(nanoseconds: 2_500_000_000)

      #expect(feeds.openFeedCount == 1)
      #expect(device.closeCount == 0)
      #expect(device.sent.count == sentBefore)
    }
  }

  @Test(arguments: [EndpointToken.readOnly, .unknown])
  func anUngrantedTokenGetsE1002AndNoVirtualGamepad(token: EndpointToken) async throws {
    let factory = FakeFeedFactory()
    let feeds = factory.registry()
    try await withEndpointServer(identity: nil, feeds: feeds) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "bridge", origins: [], scopes: [.read])
      let bridge = HostBridge(link: FakePeerChannel())
      defer { bridge.stop() }

      let failure = await Self.start(
        bridge,
        server: server,
        token: token == .unknown ? "ojd_wrong" : granted.token
      )

      guard case .endpoint(let code, _)? = failure else {
        Issue.record("Expected an endpoint error, got \(String(describing: failure)).")
        return
      }
      #expect(code == "E1002")
      #expect(factory.devices.isEmpty)
      #expect(feeds.openFeedCount == 0)
    }
  }

  // MARK: - Helpers

  enum EndpointToken: Sendable, CustomTestStringConvertible {
    case readOnly, unknown
    var testDescription: String { self == .readOnly ? "read-only token" : "unknown token" }
  }

  /// Starts the bridge on a thread of its own: the endpoint client blocks on the socket.
  private static func start(
    _ bridge: HostBridge,
    server: EndpointServer,
    token: String
  ) async -> BridgeError? {
    let credentials = EndpointCredentials(
      socketPath: server.socketPath,
      token: token,
      tokenName: "bridge"
    )
    return await offPool {
      do {
        try bridge.start(credentials)
        return nil
      } catch let error as BridgeError {
        return error
      } catch {
        return .socket("\(error)")
      }
    }
  }

}
