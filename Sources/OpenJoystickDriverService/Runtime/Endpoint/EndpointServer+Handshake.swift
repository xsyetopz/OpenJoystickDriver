import Foundation
import OpenJoystickDriverKit

extension EndpointServer {
  /// Runs one connection on a connection-queue thread: the handshake, the subscription, then a
  /// wait until either side closes. `origin` is the normalized `Origin` of a WebSocket, nil when
  /// it sent none, and `port` the port it connected to.
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
      guard connections.count < Self.maximumConnections else { return false }
      connections[ObjectIdentifier(connection)] = connection
      return true
    }
    guard accepted else {
      connection.close(
        EndpointError(
          code: .tooManyConnections,
          message: "The endpoint serves at most \(Self.maximumConnections) clients."
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
    connectionQueue.asyncAfter(deadline: .now() + .seconds(Self.handshakeSeconds)) {
      [weak connection] in
      guard let connection, connection.session == nil else { return }
      connection.close(Self.invalid("Send hello within \(Self.handshakeSeconds) seconds."))
    }
    let challenge = Challenge(nonce: nonce, origin: origin ?? "", port: port.map(String.init) ?? "")
    guard handshake(connection, peer: peer, origin: origin, challenge: challenge) else { return }
    connection.setReceiveTimeout(seconds: 0)

    guard let request = readRequest(connection) else { return }
    guard request.type == .subscribe, request.stream == "controllers" else {
      connection.close(Self.invalid("Send subscribe with the controllers stream."))
      return
    }
    guard connection.session?.scopes.contains(.read) == true else {
      connection.close(
        EndpointError(code: .notGranted, message: "Subscribe needs the read scope.")
      )
      return
    }
    lock.withLock { subscribe(connection, output: request.output ?? false) }

    // The protocol has no line after `subscribe`; any line ends the connection.
    if readRequest(connection) != nil {
      connection.close(Self.invalid("Only one subscribe is accepted."))
    }
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
    guard let hello = readRequest(connection) else { return false }
    guard hello.type == .hello, let requestedProtocol = hello.protocol,
      let requested = hello.scopes,
      !requested.isEmpty
    else {
      connection.close(Self.invalid("Send hello with a protocol and at least one scope first."))
      return false
    }
    guard requestedProtocol == Self.protocolVersion else {
      var error = EndpointError(
        code: .unsupportedProtocol,
        message: "Protocol \(requestedProtocol) is not supported."
      )
      error.supported = [Self.protocolVersion]
      connection.close(error)
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
        line: EndpointWelcome(protocol: Self.protocolVersion, version: version, scopes: scopes)
      )
      return true
    }
  }

  /// The session of a signed client, or nil after recording the refusal. Call with `lock` held.
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
        reason: "not-granted",
        at: Date()
      )
      return nil
    }
    return AccessConnection(identity: client.identity, scopes: scopes)
  }

  /// The session of a token client, or nil after recording the refusal. Call with `lock` held.
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
      kind == .socket || origin.map(grant.origins.contains) ?? grant.origins.isEmpty,
      // Any site can script a page, so only a client without `Origin` drives a pad.
      kind == .socket || origin == nil || !scopes.contains(.control)
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

  /// The next request; nil after the client closed, the timeout passed, or an invalid line, which
  /// is answered with `invalid-message`.
  private func readRequest(_ connection: EndpointConnection) -> EndpointRequest? {
    switch connection.readMessage() {
    case .end: return nil
    case .tooLong:
      connection.close(Self.invalid("A message is longer than \(Self.maximumLineBytes) bytes."))
      return nil
    case .invalid(let reason):
      connection.close(Self.invalid(reason))
      return nil
    case .message(let data):
      guard let request = try? JSONDecoder().decode(EndpointRequest.self, from: data) else {
        connection.close(Self.invalid("The message is not a request."))
        return nil
      }
      return request
    }
  }

  /// What a token client signs: the connection's nonce, and on the WebSocket its origin and port.
  struct Challenge {
    let nonce: String
    let origin: String
    let port: String
  }

  private static func invalid(_ message: String) -> EndpointError {
    EndpointError(code: .invalidMessage, message: message)
  }
}
