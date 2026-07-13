import Darwin
import Foundation

public struct LocalServiceRPCRequest: Codable, Sendable {
  public let method: String
  public let arguments: Data
}

public struct LocalServiceRPCResponse: Codable, Sendable {
  public let result: Data?
  public let error: String?

  public init(result: Data?, error: String?) {
    self.result = result
    self.error = error
  }
}

public struct LocalServiceRPCEmptyArguments: Codable, Sendable {}
public struct LocalServiceRPCBoolArguments: Codable, Sendable { public let value: Bool }
public struct LocalServiceRPCStringArguments: Codable, Sendable { public let value: String }
public struct LocalServiceRPCIntArguments: Codable, Sendable { public let value: Int }
public struct LocalServiceRPCDeviceArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
}
public struct LocalServiceRPCRumbleArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let left: Int
  public let right: Int
  public let leftTrigger: Int
  public let rightTrigger: Int
  public let durationMilliseconds: Int
}
public struct LocalServiceRPCPlayerIndicatorArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let playerIndex: Int
}
public struct LocalServiceRPCColorArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let red: Int
  public let green: Int
  public let blue: Int
}
public struct LocalServiceRPCBrightnessArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let brightness: Int
}

enum LocalServiceRPCError: Error, LocalizedError, Sendable {
  case alreadyRunning
  case connectionFailed(Int32)
  case invalidFrame
  case peerRejected
  case remote(String)
  case timeout

  var errorDescription: String? {
    switch self {
    case .alreadyRunning: return "The main application RPC service is already running."
    case .connectionFailed(let code):
      return "Could not connect to main application (errno \(code))."
    case .invalidFrame: return "Main application returned an invalid RPC frame."
    case .peerRejected: return "Main application rejected the RPC peer."
    case .remote(let message): return message
    case .timeout: return "Main application RPC timed out."
    }
  }
}

enum LocalServiceRPCTransport {
  static let maximumFrameBytes = 8 * 1_024 * 1_024
  static var defaultSocketPath: String { "/tmp/com.openjoystickdriver.\(geteuid()).rpc" }

  static func openConnectedSocket(
    timeoutSeconds: TimeInterval,
    socketPath: String = defaultSocketPath
  ) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      try setTimeout(descriptor, seconds: timeoutSeconds)
      var address = try socketAddress(path: socketPath)
      let status = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.connect(descriptor, $0, socketAddressLength(path: socketPath))
        }
      }
      guard status == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      return descriptor
    } catch {
      Darwin.close(descriptor)
      throw error
    }
  }

  static func socketAddress(path: String) throws -> sockaddr_un {
    guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
      throw LocalServiceRPCError.invalidFrame
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: path.utf8.count + 1) { buffer in
        path.withCString { source in strcpy(buffer, source) }
      }
    }
    return address
  }

  static func socketAddressLength(path: String) -> socklen_t {
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path) ?? 0
    return socklen_t(pathOffset + path.utf8.count + 1)
  }

  static func setTimeout(_ descriptor: Int32, seconds: TimeInterval) throws {
    let clamped = max(0.1, seconds)
    var timeout = timeval(
      tv_sec: Int(clamped),
      tv_usec: Int32((clamped - floor(clamped)) * 1_000_000)
    )
    let size = socklen_t(MemoryLayout<timeval>.size)
    guard
      setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size) == 0,
      setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size) == 0
    else {
      throw LocalServiceRPCError.connectionFailed(errno)
    }
  }

  static func sendFrame(_ data: Data, to descriptor: Int32) throws {
    guard data.count <= maximumFrameBytes else { throw LocalServiceRPCError.invalidFrame }
    var length = UInt32(data.count).bigEndian
    try withUnsafeBytes(of: &length) { try sendAll($0, to: descriptor) }
    try data.withUnsafeBytes { try sendAll($0, to: descriptor) }
  }

  static func receiveFrame(from descriptor: Int32) throws -> Data {
    var header = [UInt8](repeating: 0, count: 4)
    try header.withUnsafeMutableBytes { try receiveAll($0, from: descriptor) }
    let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard length <= maximumFrameBytes else { throw LocalServiceRPCError.invalidFrame }
    var data = Data(count: Int(length))
    try data.withUnsafeMutableBytes { try receiveAll($0, from: descriptor) }
    return data
  }

  private static func sendAll(
    _ bytes: UnsafeRawBufferPointer,
    to descriptor: Int32
  ) throws {
    var offset = 0
    while offset < bytes.count {
      guard let base = bytes.baseAddress else { return }
      let sent = Darwin.send(
        descriptor,
        base.advanced(by: offset),
        bytes.count - offset,
        MSG_NOSIGNAL
      )
      guard sent > 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      offset += sent
    }
  }

  private static func receiveAll(
    _ bytes: UnsafeMutableRawBufferPointer,
    from descriptor: Int32
  ) throws {
    var offset = 0
    while offset < bytes.count {
      guard let base = bytes.baseAddress else { return }
      let received = Darwin.recv(descriptor, base.advanced(by: offset), bytes.count - offset, 0)
      guard received > 0 else {
        if received < 0, errno == EAGAIN || errno == EWOULDBLOCK {
          throw LocalServiceRPCError.timeout
        }
        throw LocalServiceRPCError.invalidFrame
      }
      offset += received
    }
  }
}

public enum LocalServiceRPCClient {
  public static func isAvailable() -> Bool {
    serverProcessIdentifier() != nil
  }

  public static func serverProcessIdentifier() -> Int32? {
    serverProcessIdentifier(socketPath: LocalServiceRPCTransport.defaultSocketPath)
  }

  static func serverProcessIdentifier(socketPath: String) -> Int32? {
    guard let descriptor = try? LocalServiceRPCTransport.openConnectedSocket(
      timeoutSeconds: 0.2,
      socketPath: socketPath
    )
    else { return nil }
    defer { Darwin.close(descriptor) }
    var processIdentifier: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    guard
      getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &size) == 0,
      processIdentifier > 0
    else {
      return nil
    }
    return processIdentifier
  }

  static func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    method: String,
    arguments: Arguments,
    timeoutSeconds: TimeInterval,
    socketPath: String = LocalServiceRPCTransport.defaultSocketPath,
    as type: Value.Type = Value.self
  ) async throws -> Value {
    try await Task.detached(priority: .userInitiated) {
      let descriptor = try LocalServiceRPCTransport.openConnectedSocket(
        timeoutSeconds: timeoutSeconds,
        socketPath: socketPath
      )
      defer { Darwin.close(descriptor) }
      let request = LocalServiceRPCRequest(
        method: method,
        arguments: try JSONEncoder().encode(arguments)
      )
      try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(request), to: descriptor)
      let responseData = try LocalServiceRPCTransport.receiveFrame(from: descriptor)
      let response = try JSONDecoder().decode(LocalServiceRPCResponse.self, from: responseData)
      if let error = response.error { throw LocalServiceRPCError.remote(error) }
      guard let result = response.result else { throw LocalServiceRPCError.invalidFrame }
      return try JSONDecoder().decode(type, from: result)
    }.value
  }
}

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

  public convenience init(
    authentication: @escaping Authentication,
    handler: @escaping Handler
  ) {
    self.init(
      socketPath: LocalServiceRPCTransport.defaultSocketPath,
      authentication: authentication,
      handler: handler
    )
  }

  init(
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
          Darwin.bind(
            descriptor,
            $0,
            LocalServiceRPCTransport.socketAddressLength(path: path)
          )
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
    guard let peerPID = authenticatedPeerPID(descriptor), authentication(peerPID) else {
      Darwin.close(descriptor)
      return
    }
    do {
      try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 35)
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
    guard
      getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &size) == 0,
      processIdentifier > 0
    else {
      return nil
    }
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
