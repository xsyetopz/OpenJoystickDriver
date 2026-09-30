import Darwin
import Foundation

public struct LocalServiceRPCRequest: Codable, Sendable {
  public let method: String
  public let arguments: Data
}
public struct LocalServiceRPCResponse: Codable, Sendable {
  public let result: Data?
  public let error: String?
  public let errorCode: LocalServiceRPCErrorCode?
  /// The typed remapping failure; `error` carries its message.
  public let remappingError: ApplicationServiceRemappingRPCError?

  public init(result: Data?, error: String?, errorCode: LocalServiceRPCErrorCode? = nil) {
    self.result = result
    self.error = error
    self.errorCode = errorCode
    remappingError = nil
  }

  package init(remappingError: ApplicationServiceRemappingRPCError) {
    result = nil
    error = remappingError.message
    errorCode = nil
    self.remappingError = remappingError
  }
}

/// Transport-level failure a response carries alongside its `error` message.
public enum LocalServiceRPCErrorCode: String, Codable, Sendable { case peerRejected }

public struct LocalServiceRPCEmptyArguments: Codable, Sendable {}
public struct LocalServiceRPCBoolArguments: Codable, Sendable { public let value: Bool }
public struct LocalServiceRPCIntArguments: Codable, Sendable { public let value: Int }
public struct LocalServiceRPCPermissionArguments: Codable, Sendable {
  public let requirement: PermissionManager.Requirement

  public init(requirement: PermissionManager.Requirement) { self.requirement = requirement }
}
public struct LocalServiceRPCDeviceArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?

  public init(vendorID: Int, productID: Int, runtimeIdentifier: String? = nil) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
  }
}
/// Arguments of `sendControllerOutput`: the controller selector and one output command, whose
/// JSON shape `ControllerOutputCommand` documents. An ID outside `UInt16` fails decoding.
public struct LocalServiceRPCControllerOutputArguments: Codable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let runtimeIdentifier: String?
  public let command: ControllerOutputCommand

  public init(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
    command: ControllerOutputCommand
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.command = command
  }
}
public struct LocalServiceRPCColorArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?
  public let red: Int
  public let green: Int
  public let blue: Int

  public init(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String? = nil,
    red: Int,
    green: Int,
    blue: Int
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.red = red
    self.green = green
    self.blue = blue
  }
}
public struct LocalServiceRPCColorPreviewArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?
  public let token: UUID
  public let red: Int
  public let green: Int
  public let blue: Int

  public init(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String? = nil,
    token: UUID,
    red: Int,
    green: Int,
    blue: Int
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.token = token
    self.red = red
    self.green = green
    self.blue = blue
  }
}
public struct LocalServiceRPCColorPreviewReleaseArguments: Codable, Sendable {
  public let vendorID: Int
  public let productID: Int
  public let runtimeIdentifier: String?
  public let token: UUID

  public init(vendorID: Int, productID: Int, runtimeIdentifier: String? = nil, token: UUID) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.token = token
  }
}

package enum LocalServiceRPCError: Error, Equatable, LocalizedError, Sendable {
  case alreadyRunning
  case connectionFailed(Int32)
  case invalidFrame
  case peerRejected
  case remote(String)
  case timeout

  package var errorDescription: String? {
    switch self {
    case .alreadyRunning: return "The main application RPC service is already running."
    case .connectionFailed(let code):
      return "Could not connect to main application (errno \(code))."
    case .invalidFrame: return "Main application returned an invalid RPC frame."
    case .peerRejected:
      return "The running main application rejected this CLI executable. Use the CLI inside "
        + "/Applications/OpenJoystickDriver.app, or install and relaunch a matching signed build."
    case .remote(let message): return message
    case .timeout: return "Main application RPC timed out."
    }
  }
}
package enum LocalServiceRPCTransport {
  static let maximumFrameBytes = ApplicationServiceRemappingRPC.maximumTransportFrameBytes
  package static var defaultSocketPath: String { "/tmp/com.openjoystickdriver.\(geteuid()).rpc" }

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
    guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size) == 0,
      setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size) == 0
    else { throw LocalServiceRPCError.connectionFailed(errno) }
  }

  static func sendFrame(_ data: Data, to descriptor: Int32) throws {
    guard data.count <= maximumFrameBytes else { throw LocalServiceRPCError.invalidFrame }
    var length = UInt32(data.count).bigEndian
    try withUnsafeBytes(of: &length) { try sendAll($0, to: descriptor) }
    try data.withUnsafeBytes { try sendAll($0, to: descriptor) }
  }

  static func receiveFrame(
    from descriptor: Int32,
    closedBeforeFrameError: LocalServiceRPCError = .invalidFrame
  ) throws -> Data {
    var header = [UInt8](repeating: 0, count: 4)
    try header.withUnsafeMutableBytes {
      try receiveAll($0, from: descriptor, closedBeforeAnyBytesError: closedBeforeFrameError)
    }
    let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard length <= maximumFrameBytes else { throw LocalServiceRPCError.invalidFrame }
    var data = Data(count: Int(length))
    try data.withUnsafeMutableBytes {
      try receiveAll($0, from: descriptor, closedBeforeAnyBytesError: .invalidFrame)
    }
    return data
  }

  private static func sendAll(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) throws {
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
    from descriptor: Int32,
    closedBeforeAnyBytesError: LocalServiceRPCError
  ) throws {
    var offset = 0
    while offset < bytes.count {
      guard let base = bytes.baseAddress else { return }
      let received = Darwin.recv(descriptor, base.advanced(by: offset), bytes.count - offset, 0)
      guard received > 0 else {
        if received < 0, errno == EAGAIN || errno == EWOULDBLOCK {
          throw LocalServiceRPCError.timeout
        }
        throw offset == 0 ? closedBeforeAnyBytesError : LocalServiceRPCError.invalidFrame
      }
      offset += received
    }
  }
}

public enum LocalServiceRPCClient {}
