import Foundation
import OpenJoystickDriverKit

extension EndpointServer {
  /// Runs one connection on a connection-queue thread: the handshake, the subscription, then a
  /// wait until either side closes.
  func serve(_ connection: EndpointConnection) {
    defer {
      lock.withLock {
        connections[ObjectIdentifier(connection)] = nil
        stopStreamIfIdle()
      }
      connection.finish()
    }
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
    guard let peer = LocalSocketPeer.authenticated(connection.descriptor) else { return }
    try? LocalServiceRPCTransport.setTimeout(
      connection.descriptor,
      seconds: TimeInterval(Self.handshakeSeconds)
    )
    guard handshake(connection, peer: peer) else { return }
    connection.setReceiveTimeout(seconds: 0)

    guard let request = readRequest(connection) else { return }
    guard request.type == .subscribe, request.stream == "controllers" else {
      connection.close(Self.invalid("Send subscribe with the controllers stream."))
      return
    }
    lock.withLock { subscribe(connection, output: request.output ?? false) }

    // The protocol has no line after `subscribe`; any line ends the connection.
    if readRequest(connection) != nil {
      connection.close(Self.invalid("Only one subscribe is accepted."))
    }
  }

  /// Answers `hello` with `welcome` or an error; true when the client was welcomed.
  private func handshake(_ connection: EndpointConnection, peer: LocalSocketPeer) -> Bool {
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
    guard let client = identify(peer) else {
      connection.close(
        EndpointError(code: .notGranted, message: "The client's signature could not be read.")
      )
      return false
    }
    guard !scopes.contains(.control) else {
      connection.close(
        EndpointError(code: .notGranted, message: "The control scope is not available yet.")
      )
      return false
    }
    return lock.withLock {
      guard let file = try? store.load(), file.enabled else {
        connection.close(
          EndpointError(code: .endpointDisabled, message: "The endpoint is disabled.")
        )
        return false
      }
      guard let grant = file.grant(for: client.identity), scopes.allSatisfy(grant.scopes.contains)
      else {
        refusals.record(
          client.identity,
          path: client.path,
          scopes: scopes,
          reason: "not-granted",
          at: Date()
        )
        connection.close(
          EndpointError(code: .notGranted, message: "The client is not granted these scopes.")
        )
        return false
      }
      connection.welcome(
        client,
        scopes: scopes,
        line: EndpointWelcome(protocol: Self.protocolVersion, version: version, scopes: scopes)
      )
      return true
    }
  }

  /// The next request; nil after the client closed, the timeout passed, or an invalid line, which
  /// is answered with `invalid-message`.
  private func readRequest(_ connection: EndpointConnection) -> EndpointRequest? {
    switch connection.readLine() {
    case .end: return nil
    case .tooLong:
      connection.close(Self.invalid("A line is longer than \(Self.maximumLineBytes) bytes."))
      return nil
    case .line(let data):
      guard let request = try? JSONDecoder().decode(EndpointRequest.self, from: data) else {
        connection.close(Self.invalid("The line is not a request."))
        return nil
      }
      return request
    }
  }

  private static func invalid(_ message: String) -> EndpointError {
    EndpointError(code: .invalidMessage, message: message)
  }
}
