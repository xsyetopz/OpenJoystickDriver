import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The WebSocket and the overlay pages on `127.0.0.1`, on a port the system picks.
@Suite(.serialized)
struct EndpointWebSocketTests {
  private static let origin = "http://localhost:8080"

  @Test
  func aTokenClientStreamsControllerEventsOverTheWebSocket() throws {
    try withWeb { server, fixture, port, token in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.faceSouth]))
      let client = try EndpointWebTestClient(port: port)
      let response = try #require(
        client.request(
          "/endpoint",
          headers: EndpointWebTestClient.upgradeHeaders(port: port, origin: Self.origin)
        )
      )
      #expect(response.status == 101)
      #expect(
        response.headers["sec-websocket-accept"]
          == EndpointWebTestClient.accept(for: EndpointWebTestClient.key)
      )
      let challenge = try #require(client.readLine())
      client.send(
        tokenHello(
          name: "overlay",
          token: token,
          nonce: try client.object(challenge)["nonce"] as? String ?? "",
          origin: Self.origin,
          port: String(port)
        )
      )
      client.send(#"{"type":"subscribe","stream":"controllers"}"#)

      let lines = try [challenge] + (0..<3).map { _ in try #require(client.readLine()) }
      for line in lines {
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      }
      #expect(
        try lines.map { try client.object($0)["type"] as? String }
          == ["challenge", "welcome", "connected", "input"]
      )
      #expect(
        try server.status().connections == [
          AccessConnection(
            id: "token:overlay",
            identifier: "overlay",
            scopes: [.read],
            transport: .web
          )
        ]
      )
    }
  }

  @Test(
    arguments: [
      ("Host", "evil.example:1", 403),
      ("Host", nil, 403),
      ("Origin", "http://evil.example", 403),
      ("Origin", "null", 403),
      ("Origin", nil, 403),
      ("Upgrade", nil, 400),
      ("Sec-WebSocket-Key", "short", 400),
      ("Sec-WebSocket-Version", "8", 426),
    ] as [(String, String?, Int)]
  )
  func aBadUpgradeIsRefused(header: String, value: String?, status: Int) throws {
    try withWeb { _, _, port, _ in
      let client = try EndpointWebTestClient(port: port)
      var headers = EndpointWebTestClient.upgradeHeaders(port: port, origin: Self.origin)
      headers[header] = .some(value)

      let response = try #require(client.request("/endpoint", headers: headers))

      #expect(response.status == status)
      #expect(response.headers["sec-websocket-version"] == (status == 426 ? "13" : nil))
    }
  }

  /// `localhost` can resolve to `::1`, where another user can listen on the same port.
  @Test
  func theLocalhostHostNameIsRefused() throws {
    try withWeb { _, _, port, _ in
      let client = try EndpointWebTestClient(port: port)
      var headers = EndpointWebTestClient.upgradeHeaders(port: port, origin: Self.origin)
      headers["Host"] = "localhost:\(port)"

      #expect(client.request("/endpoint", headers: headers)?.status == 403)
    }
  }

  /// A client that sends its hello one byte at a time is closed when the handshake time ends,
  /// so slow clients cannot hold the connection slots.
  @Test
  func aHelloMustArriveWithinTheHandshakeTime() throws {
    try withWeb { _, _, port, _ in
      let client = try upgraded(port: port)
      // A masked text frame header that announces 100 bytes; its payload never completes.
      let bytes: [UInt8] =
        [0x81, 0x80 | 100, 0x12, 0x34, 0x56, 0x78] + [UInt8](repeating: 0, count: 6)
      let start = Date()
      for byte in bytes.prefix(EndpointServer.handshakeSeconds + 2) {
        client.sendBytes(Data([byte]))
        Thread.sleep(forTimeInterval: 1)
      }
      while client.readFrame() != nil {}

      #expect(Date().timeIntervalSince(start) < Double(EndpointServer.handshakeSeconds + 3))
    }
  }

  /// A proof is bound to the page's origin and the port, so a page on a port that another
  /// program took cannot pass on a challenge from the real endpoint.
  @Test(arguments: [
    "none", "wrong token", "unknown name", "other nonce", "other origin", "other port",
  ])
  func aHelloWithoutTheRightProofIsRefused(kind: String) throws {
    try withWeb { server, _, port, token in
      let client = try upgraded(port: port)
      let (name, nonce, origin, proofPort) =
        switch kind {
        case "unknown name": ("missing", client.nonce, Self.origin, port)
        case "other nonce": ("overlay", try upgraded(port: port).nonce, Self.origin, port)
        case "other origin": ("overlay", client.nonce, "http://127.0.0.1:9", port)
        case "other port": ("overlay", client.nonce, Self.origin, port + 1)
        default: ("overlay", client.nonce, Self.origin, port)
        }
      let hello =
        switch kind {
        case "none": #"{"type":"hello","protocol":1,"scopes":["read"]}"#
        default:
          tokenHello(
            name: name,
            token: kind == "wrong token" ? "ojd_wrong" : token,
            nonce: nonce,
            origin: origin,
            port: String(proofPort)
          )
        }
      client.send(hello)

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
      #expect(try server.status().refusedTokens.map(\.transport) == [.web])
      #expect(try server.status().refusedTokens.first?.origin == Self.origin)
    }
  }

  @Test
  func aTokenIsRefusedFromAnOriginItWasNotGrantedFor() throws {
    try withWeb { server, _, port, _ in
      let other = try server.grantToken(
        name: "other",
        origins: ["http://127.0.0.1:9"],
        scopes: [.read]
      )
      let client = try upgraded(port: port)
      client.send(
        tokenHello(
          name: "other",
          token: other.token,
          nonce: client.nonce,
          origin: Self.origin,
          port: String(port)
        )
      )

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(try server.status().refusedTokens.first?.name == "other")
    }
  }

  @Test
  func aTokenWithoutOriginsIsRefusedFromAPage() throws {
    try withWeb { server, _, port, _ in
      let script = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try upgraded(port: port)
      client.send(
        tokenHello(
          name: "script",
          token: script.token,
          nonce: client.nonce,
          origin: Self.origin,
          port: String(port)
        )
      )

      #expect(try client.readObject()["code"] as? String == "not-granted")
    }
  }

  /// A native client, such as a sandboxed app that cannot reach the socket, sends no `Origin`;
  /// it signs an empty origin line and the port.
  @Test
  func aTokenWithoutOriginsWorksWithoutAnOrigin() throws {
    try withWeb { server, _, port, _ in
      let script = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try upgraded(port: port, origin: nil)
      client.send(
        tokenHello(
          name: "script",
          token: script.token,
          nonce: client.nonce,
          port: String(port)
        )
      )

      #expect(try client.readObject()["type"] as? String == "welcome")
    }
  }

  /// A page never drives a pad, even with a control token granted for its origin.
  @Test
  func aControlTokenIsRefusedFromAPage() throws {
    try withWeb { server, _, port, _ in
      let pad = try server.grantToken(name: "pad", origins: [Self.origin], scopes: [.control])
      let client = try upgraded(port: port)
      client.send(
        tokenHello(
          name: "pad",
          token: pad.token,
          nonce: client.nonce,
          origin: Self.origin,
          port: String(port),
          scopes: ["control"]
        )
      )

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(client.readLine() == nil)
      #expect(try server.status().refusedTokens.first?.name == "pad")
      #expect(try server.status().refusedTokens.first?.scopes == [.control])
    }
  }

  /// A native client that cannot reach the socket, such as a Wine program, drives a pad over the
  /// WebSocket with a token that has no origins.
  @Test
  func aControlTokenWithoutOriginsWorksWithoutAnOrigin() throws {
    try withWeb { server, _, port, _ in
      let pad = try server.grantToken(name: "pad", origins: [], scopes: [.control])
      let client = try upgraded(port: port, origin: nil)
      client.send(
        tokenHello(
          name: "pad",
          token: pad.token,
          nonce: client.nonce,
          port: String(port),
          scopes: ["control"]
        )
      )

      let welcome = try client.readObject()
      #expect(welcome["type"] as? String == "welcome")
      #expect(welcome["scopes"] as? [String] == ["control"])
    }
  }

  /// Browsers always send `Origin`, so a token bound to origins is refused without one.
  @Test
  func aTokenWithOriginsIsRefusedWithoutAnOrigin() throws {
    try withWeb { server, _, port, token in
      _ = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try upgraded(port: port, origin: nil)
      client.send(
        tokenHello(name: "overlay", token: token, nonce: client.nonce, port: String(port))
      )

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(try server.status().refusedTokens.first?.name == "overlay")
    }
  }

  /// An `Origin` that is not a web origin comes from a page, not a native client, so it never
  /// counts as no origin.
  @Test(arguments: ["null", "", "chrome-extension://abc"])
  func anInvalidOriginIsRefusedWithATokenWithoutOrigins(origin: String) throws {
    try withWeb { server, _, port, _ in
      _ = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try EndpointWebTestClient(port: port)
      let headers = EndpointWebTestClient.upgradeHeaders(port: port, origin: origin)

      #expect(client.request("/endpoint", headers: headers)?.status == 403)
    }
  }

  /// Without `Origin`, the proof still covers the nonce and the port.
  @Test(arguments: ["wrong token", "other port", "socket proof"])
  func aHelloWithoutAnOriginAndTheRightProofIsRefused(kind: String) throws {
    try withWeb { server, _, port, _ in
      let script = try server.grantToken(name: "script", origins: [], scopes: [.read])
      let client = try upgraded(port: port, origin: nil)
      let proofPort =
        switch kind {
        case "other port": String(port + 1)
        case "socket proof": ""
        default: String(port)
        }
      client.send(
        tokenHello(
          name: "script",
          token: kind == "wrong token" ? "ojd_wrong" : script.token,
          nonce: client.nonce,
          port: proofPort
        )
      )

      #expect(try client.readObject()["code"] as? String == "not-granted")
      #expect(try server.status().refusedTokens.first?.name == nil)
    }
  }

  @Test
  func aFragmentedMessageIsJoined() throws {
    try withWeb { _, _, port, token in
      let client = try upgraded(port: port)
      let hello = Data(
        tokenHello(
          name: "overlay",
          token: token,
          nonce: client.nonce,
          origin: Self.origin,
          port: String(port)
        ).utf8
      )
      client.sendFrame(opcode: 0x1, payload: hello.prefix(10), final: false)
      client.sendFrame(opcode: 0x9, payload: Data("ping".utf8))
      client.sendFrame(opcode: 0x0, payload: hello.dropFirst(10))

      let pong = try #require(client.readFrame())
      #expect(pong.opcode == 0xA)
      #expect(pong.payload == Data("ping".utf8))
      #expect(try client.readObject()["type"] as? String == "welcome")
    }
  }

  @Test(arguments: ["binary", "unmasked", "oversized", "reserved"])
  func aFrameTheEndpointDoesNotAcceptEndsTheConnection(kind: String) throws {
    try withWeb { _, _, port, _ in
      let client = try upgraded(port: port)
      switch kind {
      case "binary": client.sendFrame(opcode: 0x2, payload: Data([1, 2, 3]))
      case "unmasked": client.sendFrame(opcode: 0x1, payload: Data("{}".utf8), masked: false)
      case "reserved": client.sendFrame(opcode: 0x40 | 0x1, payload: Data("{}".utf8))
      default:
        let half = Data(
          repeating: UInt8(ascii: " "),
          count: EndpointServer.maximumLineBytes / 2 + 1
        )
        client.sendFrame(opcode: 0x1, payload: half, final: false)
        client.sendFrame(opcode: 0x0, payload: half)
      }

      let frame = try #require(client.readFrame())
      #expect(frame.opcode == 0x1)
      #expect(
        try client.object(String(bytes: frame.payload, encoding: .utf8) ?? "")["code"] as? String
          == "invalid-message"
      )
      #expect(client.readFrame()?.opcode == 0x8)
    }
  }

  @Test
  func aCloseFrameIsEchoed() throws {
    try withWeb { _, _, port, _ in
      let client = try upgraded(port: port)
      client.sendFrame(opcode: 0x8, payload: Data([0x03, 0xE8]))

      let frame = try #require(client.readFrame())
      #expect(frame.opcode == 0x8)
      #expect(client.readFrame() == nil)
    }
  }

  @Test
  func disablingTheWebSocketClosesItsClientsAndFreesThePortButKeepsTheSocket() throws {
    try withWeb { server, _, port, token in
      try server.setEnabled(true)
      try server.grant(EndpointFixture.tool, path: "/Tool", scopes: [.read])
      let socketClient = try EndpointTestClient.subscribed(to: server.socketPath)
      let webClient = try EndpointWebTestClient.welcomed(
        port: port,
        origin: Self.origin,
        token: token
      )

      try server.setWebEnabled(false, port: nil)

      #expect(try webClient.readObject()["code"] as? String == "endpoint-disabled")
      #expect(throws: POSIXError.self) { try EndpointWebTestClient(port: port) }
      #expect(try server.status().web.enabled == false)
      #expect(try server.status().connections.map(\.transport) == [.socket])
      _ = socketClient
    }
  }

  @Test
  func theWebSocketIsNotReachableFromAnotherInterface() throws {
    try withWeb { _, _, port, _ in
      guard let address = Self.nonLoopbackAddress() else { return }
      #expect(throws: POSIXError.self) { try EndpointWebTestClient(port: port, address: address) }
    }
  }

  @Test
  func revokingATokenClosesItsWebConnections() throws {
    try withWeb { server, _, port, token in
      let client = try EndpointWebTestClient.welcomed(port: port, origin: Self.origin, token: token)

      _ = try server.revoke(id: "token:overlay", scopes: nil)

      #expect(try client.readObject()["code"] as? String == "revoked")
    }
  }

  @Test
  func aPortInUseIsAnErrorAndLeavesTheWebSocketOff() throws {
    try withWeb { server, _, port, _ in
      try withEndpointServer { other, _ throws in
        #expect(throws: AccessGrantStoreError.portUnavailable(port)) {
          try other.setWebEnabled(true, port: port)
        }
        #expect(try other.status().web.enabled == false)
      }
      _ = server
    }
  }

  /// The first enable without a port lets the system pick a free one, so no fixed port is there
  /// for another program to take first; later enables keep it.
  @Test
  func theFirstEnableWithoutAPortPicksOneAndKeepsIt() throws {
    try withEndpointServer { server, fixture in
      #expect(try server.status().web.port == nil)
      #expect(try server.status().web.url == nil)

      try server.setWebEnabled(true, port: nil)
      let port = try #require(server.status().web.port)
      try server.setWebEnabled(false, port: nil)
      try server.setWebEnabled(true, port: nil)

      #expect(AccessWebSettings.ports.contains(port))
      #expect(try server.status().web.port == port)
      #expect(try server.status().web.listening)
      #expect(try fixture.store.load().web.port == port)
      try withEndpointServer { other, _ in
        try other.setWebEnabled(true, port: nil)
        #expect(try other.status().web.port != port)
      }
    }
  }

  /// A listener swapped for one with the same descriptor number must not be served by the old
  /// accept loop, which would check requests against the old port.
  @Test
  func aNewPortIsServedOnlyByTheNewListener() throws {
    try withWeb { server, fixture, _, _ in
      try write("<p>pad</p>", to: "index.html", in: fixture)
      for _ in 0..<20 {
        try server.setWebEnabled(false, port: nil)
        let free = try server.openWebListener(port: 0)
        close(free.descriptor)
        try server.setWebEnabled(true, port: free.port)
        for _ in 0..<5 { #expect(page("/", port: free.port)?.status == 200) }
      }
    }
  }

  // MARK: - Pages

  @Test
  func pagesAreServedFromTheOverlaysFolder() throws {
    try withWeb { _, fixture, port, _ in
      try write("<p>pad</p>", to: "index.html", in: fixture)
      try write("body{}", to: "style/main.css", in: fixture)

      let index = try #require(page("/", port: port))
      #expect(index.status == 200)
      #expect(index.body == Data("<p>pad</p>".utf8))
      #expect(index.headers["content-type"] == "text/html; charset=utf-8")
      #expect(index.headers["cross-origin-resource-policy"] == "same-origin")
      #expect(index.headers["x-content-type-options"] == "nosniff")
      #expect(index.headers["cache-control"] == "no-store")
      #expect(index.headers["connection"] == "close")
      #expect(page("/index.html", port: port)?.body == Data("<p>pad</p>".utf8))
      #expect(
        page("/style/main.css", port: port)?.headers["content-type"] == "text/css; charset=utf-8"
      )

      let head = try #require(page("/", method: "HEAD", port: port))
      #expect(head.status == 200)
      #expect(head.body.isEmpty)
      #expect(head.headers["content-length"] == "10")
    }
  }

  @Test(
    arguments: [
      ("/missing.html", "GET", nil, 404),
      ("/style/", "GET", nil, 404),
      ("/../AccessGrants.json", "GET", nil, 404),
      ("/%2e%2e/AccessGrants.json", "GET", nil, 404),
      ("/style%2f..%2f..%2fAccessGrants.json", "GET", nil, 404),
      ("/escape", "GET", nil, 404),
      ("/", "POST", nil, 405),
      ("/", "GET", "cross-site", 403),
      ("/", "GET", "same-site", 403),
      ("/", "GET", "same-origin", 200),
      ("/", "GET", "none", 200),
    ] as [(String, String, String?, Int)]
  )
  func aPageRequestOutsideTheRulesIsRefused(
    path: String,
    method: String,
    site: String?,
    status: Int
  )
    throws
  {
    try withWeb { _, fixture, port, _ in
      try write("<p>pad</p>", to: "index.html", in: fixture)
      try write("body{}", to: "style/main.css", in: fixture)
      try FileManager.default.createSymbolicLink(
        at: fixture.pagesDirectory.appendingPathComponent("escape"),
        withDestinationURL: fixture.store.url
      )
      let client = try EndpointWebTestClient(port: port)

      let response = client.request(
        path,
        method: method,
        headers: ["Host": "127.0.0.1:\(port)", "Sec-Fetch-Site": site]
      )

      #expect(response?.status == status)
      #expect(response?.body.contains(Data("enabled".utf8)) != true)
    }
  }

  @Test
  func aPageRequestForAnotherHostIsRefused() throws {
    try withWeb { _, fixture, port, _ in
      try write("<p>pad</p>", to: "index.html", in: fixture)
      let client = try EndpointWebTestClient(port: port)

      #expect(client.request("/", headers: ["Host": "rebound.example:\(port)"])?.status == 403)
    }
  }

  // MARK: - Helpers

  /// Runs `body` with the WebSocket on and a token for `origin`; the socket stays off.
  private func withWeb(
    _ body: (EndpointServer, EndpointFixture, Int, String) throws -> Void
  ) throws {
    try withEndpointServer { server, fixture in
      try server.setWebEnabled(true, port: nil)
      let granted = try server.grantToken(name: "overlay", origins: [Self.origin], scopes: [.read])
      let port = try #require(server.status().web.port)
      try body(server, fixture, port, granted.token)
    }
  }

  private func upgraded(port: Int, origin: String? = Self.origin) throws -> EndpointWebTestClient {
    let client = try EndpointWebTestClient(port: port)
    let response = client.request(
      "/endpoint",
      headers: EndpointWebTestClient.upgradeHeaders(port: port, origin: origin)
    )
    #expect(response?.status == 101)
    try client.readChallenge()
    return client
  }

  private func page(
    _ path: String,
    method: String = "GET",
    port: Int
  ) -> EndpointWebTestClient.Response? {
    try? EndpointWebTestClient(port: port).request(
      path,
      method: method,
      headers: ["Host": "127.0.0.1:\(port)"]
    )
  }

  private func write(_ text: String, to path: String, in fixture: EndpointFixture) throws {
    let url = fixture.pagesDirectory.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  /// An IPv4 address of this Mac that is not loopback, if it has one.
  private static func nonLoopbackAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
      guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
        entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0
      else { continue }
      var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      var ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        $0.pointee.sin_addr
      }
      inet_ntop(AF_INET, &ipv4, &text, socklen_t(text.count))
      return String(cString: text)
    }
    return nil
  }
}
