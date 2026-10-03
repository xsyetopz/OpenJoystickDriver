import Darwin
import Foundation
import OpenJoystickDriverKit

/// The opt-in socket on which granted local programs read controller events.
///
/// `AccessGrants.json` says whether it listens and which signed clients it serves; the socket
/// exists only while the endpoint is enabled.
///
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `lock`. Grant and
///   revoke changes and the handshake's grant check hold it too, so a client cannot be welcomed
///   with a grant that a concurrent revoke already removed.
final class EndpointServer: @unchecked Sendable {
  typealias Identify = @Sendable (LocalSocketPeer) -> EndpointClient?

  static let protocolVersion = 1
  static let maximumConnections = 8
  static let maximumLineBytes = 65_536
  static let handshakeSeconds = 5
  static let maximumQueuedLines = 256
  static let socketName = "com.openjoystickdriver.endpoint.sock"

  /// The socket in the per-user temporary folder, which only the user can open.
  static var defaultSocketPath: String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
    let directory =
      length > 0
      ? String(bytes: buffer.prefix(length - 1).map(UInt8.init(bitPattern:)), encoding: .utf8)
      : nil
    return URL(fileURLWithPath: directory ?? NSTemporaryDirectory())
      .appendingPathComponent(socketName).path
  }

  let socketPath: String
  let store: AccessGrantStore
  let source: any ControllerWatchSource
  let version: String
  let identify: Identify
  let lock = NSLock()
  private let acceptQueue = DispatchQueue(label: "com.openjoystickdriver.endpoint.accept")
  let connectionQueue = DispatchQueue(
    label: "com.openjoystickdriver.endpoint.connections",
    attributes: .concurrent
  )
  private var listeningDescriptor: Int32 = -1
  /// Every accepted connection, including those still in the handshake.
  var connections: [ObjectIdentifier: EndpointConnection] = [:]
  var refusals = AccessRefusalLog()
  var stream = EndpointStream()

  init(
    socketPath: String = EndpointServer.defaultSocketPath,
    store: AccessGrantStore = AccessGrantStore(),
    source: any ControllerWatchSource,
    version: String = ApplicationVersion.current,
    identify: @escaping Identify = EndpointClient.identify
  ) {
    self.socketPath = socketPath
    self.store = store
    self.source = source
    self.version = version
    self.identify = identify
  }

  /// Listens when the endpoint is enabled; a damaged grants file keeps it closed.
  func start() {
    do {
      guard try store.load().enabled else { return }
      try lock.withLock { try listen() }
    } catch {
      print("[EndpointServer] Not listening: \(error.localizedDescription)")
    }
  }

  /// Stops listening and closes every connection; the grants file is left as it is.
  func stop() {
    lock.withLock {
      stopListening()
      stream.stop()
      for connection in connections.values { connection.close(nil) }
    }
  }

  func status() throws -> AccessStatusPayload {
    try lock.withLock {
      let file = try store.load()
      return AccessStatusPayload(
        enabled: file.enabled,
        socketPath: socketPath,
        connections: connections.values.compactMap { connection in
          connection.session.map {
            AccessConnection(identity: $0.client.identity, scopes: $0.scopes)
          }
        }.sorted { ($0.identifier, $0.id) < ($1.identifier, $1.id) },
        grants: file.grants.map(AccessGrantSummary.init),
        refused: refusals.clients(at: Date())
      )
    }
  }

  /// Saves the flag and opens or removes the socket; disabling closes every connection with
  /// `endpoint-disabled`.
  func setEnabled(_ enabled: Bool) throws {
    try lock.withLock {
      var file = try store.load()
      file.enabled = enabled
      if enabled {
        let wasListening = listeningDescriptor >= 0
        if !wasListening { try listen() }
        do { try store.save(file) } catch {
          if !wasListening { stopListening() }
          throw error
        }
      } else {
        try store.save(file)
        stopListening()
        let error = EndpointError(code: .endpointDisabled, message: "The endpoint was disabled.")
        for connection in connections.values { connection.close(error) }
      }
    }
  }

  @discardableResult
  func grant(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) throws -> AccessGrantSummary {
    guard identity.requirement != nil else {
      throw AccessGrantStoreError.notGrantable(identity.kind)
    }
    guard !scopes.isEmpty else { throw AccessGrantStoreError.noScope }
    return try lock.withLock {
      var file = try store.load()
      let grant = file.grant(identity, scopes: scopes, path: path, at: Date())
      try store.save(file)
      refusals.remove(id: identity.accessID)
      return AccessGrantSummary(grant)
    }
  }

  /// Removes `scopes`, or the whole grant when nil, and closes with `revoked` every connection
  /// that holds a scope no longer granted.
  func revoke(id: String, scopes: [EndpointScope]?) throws -> AccessRevokeResult {
    try lock.withLock {
      var file = try store.load()
      let remaining = try file.revoke(id: id, scopes: scopes)
      try store.save(file)
      var closed = 0
      for connection in connections.values {
        guard let session = connection.session, session.client.identity.accessID == id,
          !session.scopes.allSatisfy({ remaining?.scopes.contains($0) ?? false })
        else { continue }
        connection.close(EndpointError(code: .revoked, message: "The client's grant was revoked."))
        closed += 1
      }
      return AccessRevokeResult(
        id: id,
        grant: remaining.map(AccessGrantSummary.init),
        closedConnections: closed
      )
    }
  }

  // MARK: - Socket

  /// Call with `lock` held.
  private func listen() throws {
    guard listeningDescriptor < 0 else { return }
    try removeStaleSocket()
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      var address = try LocalServiceRPCTransport.socketAddress(path: socketPath)
      let bindStatus = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(
            descriptor,
            $0,
            LocalServiceRPCTransport.socketAddressLength(path: socketPath)
          )
        }
      }
      guard bindStatus == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      guard chmod(socketPath, S_IRUSR | S_IWUSR) == 0, Darwin.listen(descriptor, 16) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
    } catch {
      Darwin.close(descriptor)
      unlink(socketPath)
      throw error
    }
    listeningDescriptor = descriptor
    acceptQueue.async { [weak self] in self?.acceptConnections(descriptor) }
  }

  /// Call with `lock` held.
  private func stopListening() {
    guard listeningDescriptor >= 0 else { return }
    shutdown(listeningDescriptor, SHUT_RDWR)
    Darwin.close(listeningDescriptor)
    listeningDescriptor = -1
    unlink(socketPath)
  }

  /// Removes a socket file that a stopped service left behind; refuses any other file.
  private func removeStaleSocket() throws {
    var information = stat()
    guard lstat(socketPath, &information) == 0 else { return }
    guard information.st_uid == geteuid(), information.st_mode & S_IFMT == S_IFSOCK else {
      throw LocalServiceRPCError.peerRejected
    }
    guard unlink(socketPath) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
  }

  private func acceptConnections(_ descriptor: Int32) {
    while lock.withLock({ listeningDescriptor == descriptor }) {
      let accepted = Darwin.accept(descriptor, nil, nil)
      guard accepted >= 0 else {
        if errno == EINTR { continue }
        return
      }
      var noSignal: Int32 = 1
      setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
      connectionQueue.async { [weak self] in
        guard let self else {
          Darwin.close(accepted)
          return
        }
        self.serve(EndpointConnection(descriptor: accepted))
      }
    }
  }
}
