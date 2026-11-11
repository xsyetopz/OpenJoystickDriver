import Foundation
import Testing

@testable import BridgeCore
@testable import WebRTCBridgeCore

extension ListeningSocketSuites {
  /// Checks the proof, the frame translation, the handshake and a loopback of both bridges.
  final class BridgeTests {
    /// The proof equals the values that the reference client computes.
    @Test
    func proofMatchesTheReferenceClientVectors() {
      // Computed with `proof()` of Scripts/SDK/reference_client.py, not with this package.
      #expect(
        EndpointSession.proof(token: "ojd_x", nonce: "abc")
          == "7ec5c93f68b657c0ecffc781972b4f9f330a1015402afd3d0ff980c90c26a738"
      )
      #expect(
        EndpointSession.proof(
          token: "ojd_test_token",
          nonce: "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"
        ) == "5944d41d5cf05ebd966fe93b5273fdaf0ed5d19c337f3176139f9c18455952ff"
      )
    }

    /// A `MODIFIED` watch line becomes a `Frame` with only known buttons and scaled axes.
    @Test
    func aWatchLineBecomesAFrame() throws {
      let line = Self.modified(pressed: ["South", "unknown-control"], hat: "NorthEast")
      let (id, frame) = try #require(FrameTranslation.frame(fromWatchLine: line))
      #expect(id == "pad-1")
      #expect((frame["kind"] as? String) == "Frame")
      #expect((frame["buttons"] as? [String]) == ["South"])
      #expect((frame["dpad"] as? [String]) == ["DpadUp", "DpadRight"])
      let axes = try #require(frame["axes"] as? [String: Double])
      #expect(axes["LeftStickY"] == 1)
      #expect(axes["RightTrigger"] == 1)
      #expect(FrameTranslation.frame(fromWatchLine: ["type": "ADDED", "object": [:]]) == nil)
    }

    /// The endpoint refuses a wrong token, and the error carries the endpoint's code.
    @Test
    func aWrongTokenIsRefused() throws {
      let endpoint = try FakeEndpoint()
      endpoint.serve(connections: 1)
      let error = #expect(throws: BridgeError.self) {
        try EndpointSession.connect(
          socketPath: endpoint.path,
          token: "wrong",
          tokenName: FakeEndpoint.tokenName,
          scopes: ["Read"]
        )
      }
      #expect(error?.description.hasPrefix("E1002") == true)
    }

    /// Two bridges in one process, joined by a real data channel: a controller frame goes from the
    /// player to the host's virtual gamepad, and the rumble command goes back.
    @Test
    func loopbackPassesAFrameOneWayAndRumbleBack() async throws {
      let rumble: [String: Any] = [
        "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": "SetRumble",
        "intensities": [
          "lowFrequency": 65535, "highFrequency": 0, "leftTrigger": 0, "rightTrigger": 0,
          "leftHaptic": 0, "rightHaptic": 0,
        ],
        "durationMilliseconds": 200,
      ]
      let hostEndpoint = try FakeEndpoint(rumble: rumble)
      let playerEndpoint = try FakeEndpoint(watchLines: [
        [
          "type": "ADDED",
          "object": ["apiVersion": endpointAPIVersion, "kind": "Controller", "id": "pad-1"],
        ],
        Self.modified(pressed: ["South"], hat: "Neutral"),
      ])
      hostEndpoint.serve(connections: 1)
      playerEndpoint.serve(connections: 1)

      let player = try PeerLink(role: .offer)
      let host = try PeerLink(role: .answer)
      let offer = try await player.localBlob()
      try await host.accept(offer)
      let answer = try await host.localBlob()
      try await player.accept(answer)
      await player.waitUntilOpen()
      await host.waitUntilOpen()

      let (received, receivedSignal) = AsyncStream.makeStream(of: Void.self)
      let hostBridge = HostBridge(link: host)
      let playerBridge = PlayerBridge(link: player)
      nonisolated(unsafe) var rumbleLine: [String: Any]?
      playerBridge.onRumble = { line in
        rumbleLine = line
        receivedSignal.yield()
        receivedSignal.finish()
      }
      try hostBridge.start(
        EndpointCredentials(
          socketPath: hostEndpoint.path,
          token: FakeEndpoint.token,
          tokenName: FakeEndpoint.tokenName
        )
      )
      try playerBridge.start(
        EndpointCredentials(
          socketPath: playerEndpoint.path,
          token: FakeEndpoint.token,
          tokenName: FakeEndpoint.tokenName
        )
      )

      // The player receives the rumble command, or the stream ends after 20 seconds without it.
      let timeout = Task {
        try await Task.sleep(nanoseconds: 20_000_000_000)
        receivedSignal.finish()
      }
      for await _ in received { break }
      timeout.cancel()
      #expect((rumbleLine?["type"] as? String) == "SetRumble")
      #expect((rumbleLine?["intensities"] as? [String: Int])?["lowFrequency"] == 65535)

      let host1 = hostEndpoint.snapshot()
      #expect((host1.requests.first?["kind"] as? String) == "FeedRequest")
      #expect(host1.proofs == [true])
      #expect(host1.frames.contains { ($0["buttons"] as? [String]) == ["South"] })
      let player1 = playerEndpoint.snapshot()
      #expect((player1.requests.first?["kind"] as? String) == "Subscription")
      #expect(player1.proofs == [true])

      // Both fake endpoints closed their listening sockets after one accept; the bridges and the
      // WebRTC stack must not hold any listening socket.
      try await Task.sleep(nanoseconds: 300_000_000)
      #expect(ListeningSockets.ofThisProcess().isEmpty)

      // The peer sent no frame after the first, so the host keeps the feed open with KeepAlive.
      try await Task.sleep(nanoseconds: 1_200_000_000)
      #expect(hostEndpoint.keepAliveCount() >= 1)

      hostBridge.stop()
      playerBridge.stop()
      host.close()
      player.close()
    }

    /// The scan finds the listening socket of a fake endpoint that has not served.
    @Test
    func theScanSeesAListeningSocket() throws {
      let endpoint = try FakeEndpoint()
      #expect(ListeningSockets.ofThisProcess().count == 1)
      endpoint.serve(connections: 0)
    }

    /// A `MODIFIED` watch line of the controller `pad-1` with the given buttons and hat.
    private static func modified(pressed: [String], hat: String) -> [String: Any] {
      [
        "type": "MODIFIED",
        "object": [
          "apiVersion": endpointAPIVersion, "kind": "Controller", "id": "pad-1",
          "input": [
            "pressed": pressed, "hat": hat, "leftStick": ["x": 0, "y": 32767],
            "rightStick": ["x": 0, "y": 0], "leftTrigger": 0, "rightTrigger": 65535, "touch": [],
          ],
        ],
      ]
    }
  }
}
