import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

extension EndpointServer {
  /// Runs one connection on a thread of its own: the handshake, then the subscription or
  /// the feed until either side closes. `origin` is the normalized `Origin` of a WebSocket, nil
  /// when it sent none, and `port` the port it connected to.
  func serve(_ connection: EndpointConnection, origin: String? = nil, port: Int? = nil) {
    defer {
      lock.withLock {
        connections[ObjectIdentifier(connection)] = nil
        stopStreamIfIdle()
      }
      connection.finish()
    }
    // The challenge comes first, so that a client can read one line before any error.
    let nonce = AccessTokenGrant.randomBase64URL()
    connection.send(EndpointChallenge(nonce: nonce))
    let accepted = lock.withLock { () -> Bool in
      let sameTransport = connections.values.filter { $0.kind == connection.kind }.count
      guard sameTransport < Self.maximumConnections else { return false }
      connections[ObjectIdentifier(connection)] = connection
      return true
    }
    guard accepted else {
      connection.close(
        EndpointError(
          code: .tooManyConnections,
          message: "The endpoint serves at most \(Self.maximumConnections) clients per transport."
        )
      )
      return
    }
    // A TCP peer has no user or audit token; the WebSocket relies on the token alone.
    let peer = LocalSocketPeer.authenticated(connection.descriptor)
    guard connection.kind == .web || peer != nil else { return }
    try? LocalServiceRPCTransport.setTimeout(
      connection.descriptor,
      seconds: TimeInterval(Self.handshakeSeconds)
    )
    // The receive timeout restarts with each byte; this bounds the whole handshake.
    // A thread of its own waits out the time and ends early when the handshake does.
    let handshakeEnded = DispatchSemaphore(value: 0)
    BlockingWork.detachThread(name: "com.openjoystickdriver.endpoint.handshake-timer") {
      [weak connection] in
      guard handshakeEnded.wait(timeout: .now() + .seconds(Self.handshakeSeconds)) == .timedOut,
        let connection, connection.session == nil
      else { return }
      connection.close(Self.invalid("Send hello within \(Self.handshakeSeconds) seconds."))
    }
    let challenge = Challenge(nonce: nonce, origin: origin ?? "", port: port.map(String.init) ?? "")
    let welcomed = handshake(connection, peer: peer, origin: origin, challenge: challenge)
    handshakeEnded.signal()
    guard welcomed else { return }
    connection.setReceiveTimeout(seconds: 0)

    guard let request = readRequest(connection, accepting: ["Subscription", "FeedRequest"]) else {
      return
    }
    if request.kind == .feedRequest {
      guard connection.session?.scopes.contains(.control) == true else {
        connection.close(
          EndpointError(code: .notGranted, message: "FeedRequest needs the control scope.")
        )
        return
      }
      guard let persona = request.as.flatMap(VirtualHIDProfileID.init(rawValue:)) else {
        connection.close(
          Self.invalid(
            "Send FeedRequest with a persona: "
              + VirtualHIDProfileID.allCases.map(\.rawValue).joined(separator: ", ") + "."
          )
        )
        return
      }
      feed(connection, persona: persona)
      return
    }
    guard request.kind == .subscription, request.stream == "Controllers" else {
      connection.close(
        Self.invalid("Send Subscription with the Controllers stream, or FeedRequest.")
      )
      return
    }
    guard connection.session?.scopes.contains(.read) == true else {
      connection.close(
        EndpointError(code: .notGranted, message: "Subscription needs the read scope.")
      )
      return
    }
    lock.withLock { subscribe(connection, output: request.output ?? false) }

    // The protocol has no line after `Subscription`; any line ends the connection.
    _ = readRequest(connection, accepting: [])
  }

  /// Answers `hello` with `welcome` or an error; true when the client was welcomed.
  ///
  /// A `hello` with a token name is checked against the token grants and skips the signature; on
  /// the WebSocket a token is required and must be granted for the page's origin, or have no
  /// origins when the client sent no `Origin`. A page cannot ask for `control`.
  private func handshake(
    _ connection: EndpointConnection,
    peer: LocalSocketPeer?,
    origin: String?,
    challenge: Challenge
  ) -> Bool {
    guard let hello = readRequest(connection, accepting: ["Hello"]) else { return false }
    guard let requested = hello.scopes, !requested.isEmpty else {
      connection.close(Self.invalid("Send Hello with at least one scope first."))
      return false
    }
    let scopes = EndpointScope.allCases.filter(requested.contains)
    var client: EndpointClient?
    if hello.tokenName == nil, let peer {
      client = identify(peer)
      guard client != nil else {
        connection.close(
          EndpointError(code: .notGranted, message: "The client's signature could not be read.")
        )
        return false
      }
    }
    return lock.withLock {
      guard let file = try? store.load(),
        connection.kind == .web ? file.web.enabled : file.enabled
      else {
        connection.close(
          EndpointError(code: .endpointDisabled, message: "The endpoint is disabled.")
        )
        return false
      }
      let session =
        if let client { clientSession(client, scopes: scopes, file: file) } else {
          tokenSession(
            hello,
            challenge: challenge,
            scopes: scopes,
            kind: connection.kind,
            origin: origin,
            file: file
          )
        }
      guard let session else {
        connection.close(
          EndpointError(code: .notGranted, message: "The client is not granted these scopes.")
        )
        return false
      }
      connection.welcome(
        session,
        line: EndpointWelcome(version: version, scopes: scopes)
      )
      return true
    }
  }

  /// The session of a signed client, or nil after recording the refusal.
  ///
  /// Call with `lock` held.
  private func clientSession(
    _ client: EndpointClient,
    scopes: [EndpointScope],
    file: AccessGrantFile
  ) -> AccessConnection? {
    guard let grant = file.grant(for: client.identity), scopes.allSatisfy(grant.scopes.contains)
    else {
      refusals.record(
        client.identity,
        path: client.path,
        scopes: scopes,
        at: Date()
      )
      return nil
    }
    return AccessConnection(identity: client.identity, scopes: scopes)
  }

  /// The session of a token client, or nil after recording the refusal.
  ///
  /// Call with `lock` held.
  ///
  /// The refusal names the token only when the proof is right, so that a guessed name is not
  /// recorded as that token's.
  private func tokenSession(
    _ hello: EndpointRequest,
    challenge: Challenge,
    scopes: [EndpointScope],
    kind: AccessTransport,
    origin: String?,
    file: AccessGrantFile
  ) -> AccessConnection? {
    let named = file.tokens.first { $0.name == hello.tokenName }
    let grant = named.flatMap { grant in
      hello.proof.flatMap {
        grant.accepts(
          proof: $0,
          nonce: challenge.nonce,
          origin: challenge.origin,
          port: challenge.port
        ) ? grant : nil
      }
    }
    guard let grant, scopes.allSatisfy(grant.scopes.contains),
      // A token with no origins never serves a page, and no token with origins holds `control`,
      // so a page never drives a pad.
      kind == .socket || origin.map(grant.origins.contains) ?? grant.origins.isEmpty
    else {
      refusals.recordToken(
        name: grant?.name,
        origin: origin,
        transport: kind,
        scopes: scopes,
        at: Date()
      )
      return nil
    }
    return AccessConnection(id: grant.id, identifier: grant.name, scopes: scopes, transport: kind)
  }

  /// The next request, one of the `accepted` kinds; nil after the client closed, the timeout
  /// passed, or a line that is refused: see ``EndpointHeader`` for `E1009` to `E1011`, and `E1003`
  /// for a line that is not a request.
  ///
  /// With no `accepted` kind, any request is refused.
  private func readRequest(
    _ connection: EndpointConnection,
    accepting accepted: [String]
  ) -> EndpointRequest? {
    switch connection.readMessage() {
    case .end: return nil
    case .tooLong:
      connection.close(Self.invalid("A message is longer than \(Self.maximumLineBytes) bytes."))
      return nil
    case .invalid(let reason):
      connection.close(Self.invalid(reason))
      return nil
    case .message(let data):
      if let refusal = EndpointHeader.refusal(of: data, accepting: accepted) {
        connection.close(refusal)
        return nil
      }
      guard let request = try? JSONDecoder().decode(EndpointRequest.self, from: data) else {
        connection.close(Self.invalid("The message is not a valid request of its kind."))
        return nil
      }
      return request
    }
  }

  /// What a token client signs: the connection's nonce, and on the WebSocket its origin and port.
  struct Challenge {
    /// The random value that the server sent for this connection.
    let nonce: String
    /// The `Origin` of the connection, empty when it has none.
    let origin: String
    /// The port the connection reached, as text.
    let port: String
  }

  /// An `InvalidMessage` error with `message`.
  static func invalid(_ message: String) -> EndpointError {
    EndpointError(code: .invalidMessage, message: message)
  }
}
