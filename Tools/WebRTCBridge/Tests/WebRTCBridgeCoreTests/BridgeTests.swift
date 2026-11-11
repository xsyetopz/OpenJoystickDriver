import XCTest

@testable import BridgeCore
@testable import WebRTCBridgeCore

/// Checks the proof, the frame translation, the handshake and a loopback of both bridges.
final class BridgeTests: XCTestCase {
  /// The proof equals the values that the reference client computes.
  func testProofMatchesTheReferenceClientVectors() {
    // Computed with `proof()` of Scripts/SDK/reference_client.py, not with this package.
    XCTAssertEqual(
      EndpointSession.proof(token: "ojd_x", nonce: "abc"),
      "7ec5c93f68b657c0ecffc781972b4f9f330a1015402afd3d0ff980c90c26a738"
    )
    XCTAssertEqual(
      EndpointSession.proof(
        token: "ojd_test_token",
        nonce: "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"
      ),
      "5944d41d5cf05ebd966fe93b5273fdaf0ed5d19c337f3176139f9c18455952ff"
    )
  }

  /// A `MODIFIED` watch line becomes a `Frame` with only known buttons and scaled axes.
  func testAWatchLineBecomesAFrame() throws {
    let line = Self.modified(pressed: ["South", "unknown-control"], hat: "NorthEast")
    let (id, frame) = try XCTUnwrap(FrameTranslation.frame(fromWatchLine: line))
    XCTAssertEqual(id, "pad-1")
    XCTAssertEqual(frame["kind"] as? String, "Frame")
    XCTAssertEqual(frame["buttons"] as? [String], ["South"])
    XCTAssertEqual(frame["dpad"] as? [String], ["DpadUp", "DpadRight"])
    let axes = try XCTUnwrap(frame["axes"] as? [String: Double])
    XCTAssertEqual(axes["LeftStickY"], 1)
    XCTAssertEqual(axes["RightTrigger"], 1)
    XCTAssertNil(FrameTranslation.frame(fromWatchLine: ["type": "ADDED", "object": [:]]))
  }

  /// The endpoint refuses a wrong token, and the error carries the endpoint's code.
  func testAWrongTokenIsRefused() throws {
    let endpoint = try FakeEndpoint()
    endpoint.serve(connections: 1)
    XCTAssertThrowsError(
      try EndpointSession.connect(
        socketPath: endpoint.path,
        token: "wrong",
        tokenName: FakeEndpoint.tokenName,
        scopes: ["Read"]
      )
    ) { error in
      XCTAssertEqual((error as? BridgeError)?.description.hasPrefix("E1002"), true)
    }
  }

  /// Two bridges in one process, joined by a real data channel: a controller frame goes from the
  /// player to the host's virtual gamepad, and the rumble command goes back.
  func testLoopbackPassesAFrameOneWayAndRumbleBack() async throws {
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

    let received = expectation(description: "the player receives the rumble command")
    let hostBridge = HostBridge(link: host)
    let playerBridge = PlayerBridge(link: player)
    nonisolated(unsafe) var rumbleLine: [String: Any]?
    playerBridge.onRumble = { line in
      rumbleLine = line
      received.fulfill()
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

    await fulfillment(of: [received], timeout: 20)
    XCTAssertEqual(rumbleLine?["type"] as? String, "SetRumble")
    XCTAssertEqual((rumbleLine?["intensities"] as? [String: Int])?["lowFrequency"], 65535)

    let host1 = hostEndpoint.snapshot()
    XCTAssertEqual(host1.requests.first?["kind"] as? String, "FeedRequest")
    XCTAssertEqual(host1.proofs, [true])
    XCTAssertTrue(host1.frames.contains { ($0["buttons"] as? [String]) == ["South"] })
    let player1 = playerEndpoint.snapshot()
    XCTAssertEqual(player1.requests.first?["kind"] as? String, "Subscription")
    XCTAssertEqual(player1.proofs, [true])

    // Both fake endpoints closed their listening sockets after one accept; the bridges and the
    // WebRTC stack must not hold any listening socket.
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(ListeningSockets.ofThisProcess(), [])

    // The peer sent no frame after the first, so the host keeps the feed open with KeepAlive.
    try await Task.sleep(nanoseconds: 1_200_000_000)
    XCTAssertGreaterThanOrEqual(hostEndpoint.keepAliveCount(), 1)

    hostBridge.stop()
    playerBridge.stop()
    host.close()
    player.close()
  }

  /// The scan finds the listening socket of a fake endpoint that has not served.
  func testTheScanSeesAListeningSocket() throws {
    let endpoint = try FakeEndpoint()
    XCTAssertEqual(ListeningSockets.ofThisProcess().count, 1)
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
