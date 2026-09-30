import Darwin
import Foundation

public final class LocalServiceRPCServer: @unchecked Sendable {
  public typealias Authentication = @Sendable (Int32) -> Bool
  public typealias Completion = @Sendable (LocalServiceRPCResponse) -> Void
  public typealias Handler = @Sendable (LocalServiceRPCRequest, @escaping Completion) -> Void

  private let authentication: Authentication
  private let handler: Handler
  private let socketPath: String
  private let stateLock = NSLock()
  private let acceptQueue = DispatchQueue(label: "com.openjoystickdriver.rpc.accept")
  private let connectionQueue = DispatchQueue(
    label: "com.openjoystickdriver.rpc.connections",
    attributes: .concurrent
  )
  private var listeningDescriptor: Int32 = -1

  public convenience init(authentication: @escaping Authentication, handler: @escaping Handler) {
    self.init(
      socketPath: LocalServiceRPCTransport.defaultSocketPath,
      authentication: authentication,
      handler: handler
    )
  }

  package init(
    socketPath: String,
    authentication: @escaping Authentication,
    handler: @escaping Handler
  ) {
    self.socketPath = socketPath
    self.authentication = authentication
    self.handler = handler
  }

  public func start() throws {
    let path = socketPath
    try removeStaleSocket(at: path)
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      var address = try LocalServiceRPCTransport.socketAddress(path: path)
      let bindStatus = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(descriptor, $0, LocalServiceRPCTransport.socketAddressLength(path: path))
        }
      }
      guard bindStatus == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      guard Darwin.listen(descriptor, 16) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      stateLock.withLock { listeningDescriptor = descriptor }
      acceptQueue.async { [weak self] in self?.acceptConnections(descriptor) }
    } catch {
      Darwin.close(descriptor)
      unlink(path)
      throw error
    }
  }

  public func stop() {
    let descriptor = stateLock.withLock { () -> Int32 in
      let current = listeningDescriptor
      listeningDescriptor = -1
      return current
    }
    guard descriptor >= 0 else { return }
    shutdown(descriptor, SHUT_RDWR)
    Darwin.close(descriptor)
    unlink(socketPath)
  }

  private func acceptConnections(_ descriptor: Int32) {
    while stateLock.withLock({ listeningDescriptor == descriptor }) {
      let connection = Darwin.accept(descriptor, nil, nil)
      guard connection >= 0 else {
        if errno == EINTR { continue }
        return
      }
      connectionQueue.async { [weak self] in self?.handleConnection(connection) }
    }
  }

  private func handleConnection(_ descriptor: Int32) {
    guard let peerPID = authenticatedPeerPID(descriptor) else {
      Darwin.close(descriptor)
      return
    }
    do {
      try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 35)
      guard authentication(peerPID) else {
        let response = LocalServiceRPCResponse(
          result: nil,
          error: LocalServiceRPCError.peerRejected.localizedDescription,
          errorCode: .peerRejected
        )
        try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(response), to: descriptor)
        Darwin.close(descriptor)
        return
      }
      let data = try LocalServiceRPCTransport.receiveFrame(from: descriptor)
      let request = try JSONDecoder().decode(LocalServiceRPCRequest.self, from: data)
      handler(request) { response in
        defer { Darwin.close(descriptor) }
        guard let encoded = try? JSONEncoder().encode(response) else { return }
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
    } catch {
      let response = LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      Darwin.close(descriptor)
    }
  }

  private func authenticatedPeerPID(_ descriptor: Int32) -> Int32? {
    var userID: uid_t = 0
    var groupID: gid_t = 0
    guard getpeereid(descriptor, &userID, &groupID) == 0, userID == geteuid() else { return nil }
    var processIdentifier: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &size) == 0,
      processIdentifier > 0
    else { return nil }
    return processIdentifier
  }

  private func removeStaleSocket(at path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    if LocalServiceRPCClient.serverProcessIdentifier(socketPath: path) != nil {
      throw LocalServiceRPCError.alreadyRunning
    }
    var information = stat()
    guard lstat(path, &information) == 0 else { return }
    guard information.st_uid == geteuid(), information.st_mode & S_IFMT == S_IFSOCK else {
      throw LocalServiceRPCError.peerRejected
    }
    guard unlink(path) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
  }
}
