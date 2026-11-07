import Darwin
import Foundation

/// One request frame: the method name and its JSON-encoded arguments.
public struct LocalServiceRPCRequest: Codable, Sendable {
  /// The name of the called method; see ``ApplicationServiceRPCMethod``.
  public let method: String
  /// The JSON-encoded arguments.
  public let arguments: Data
}
/// One response frame: the JSON-encoded result, or the error the call ended with.
public struct LocalServiceRPCResponse: Codable, Sendable {
  /// The JSON-encoded result; nil when the call failed.
  public let result: Data?
  /// The message of the failure; nil when the call succeeded.
  public let error: String?
  /// The transport-level code of the failure; nil for other failures.
  public let errorCode: LocalServiceRPCErrorCode?
  /// The typed remapping failure; `error` carries its message.
  public let remappingError: ApplicationServiceRemappingRPCError?

  /// Creates a response from a result or an error message.
  public init(result: Data?, error: String?, errorCode: LocalServiceRPCErrorCode? = nil) {
    self.result = result
    self.error = error
    self.errorCode = errorCode
    remappingError = nil
  }

  /// Creates the response of a remapping failure; its message becomes `error`.
  package init(remappingError: ApplicationServiceRemappingRPCError) {
    result = nil
    error = remappingError.message
    errorCode = nil
    self.remappingError = remappingError
  }
}

/// The transport-level failures that a response reports with a code.
public enum LocalServiceRPCErrorCode: String, Codable, Sendable {
  /// The server refused the peer.
  case peerRejected
}

/// The arguments of a method that takes none.
public struct LocalServiceRPCEmptyArguments: Codable, Sendable {}
/// The arguments of `requestAccess`.
public struct LocalServiceRPCPermissionArguments: Codable, Sendable {
  /// The permission to request.
  public let requirement: PermissionManager.Requirement

  /// Creates the arguments for `requirement`.
  public init(requirement: PermissionManager.Requirement) { self.requirement = requirement }
}
/// The arguments of a method that names one controller.
public struct LocalServiceRPCDeviceArguments: Codable, Sendable {
  /// The controller the method acts on.
  public let controller: ControllerReference

  /// Creates the arguments for `controller`.
  public init(controller: ControllerReference) {
    self.controller = controller
  }
}
/// Arguments of `sendControllerOutput`: the controller reference and one output command, whose
/// JSON shape `ControllerOutputCommand` documents.
public struct LocalServiceRPCControllerOutputArguments: Codable, Sendable {
  /// The controller to send the command to.
  public let controller: ControllerReference
  /// The output command.
  public let command: ControllerOutputCommand

  /// Creates the arguments from a controller and a command.
  public init(
    controller: ControllerReference,
    command: ControllerOutputCommand
  ) {
    self.controller = controller
    self.command = command
  }
}
/// Arguments of `playControllerSpeaker`: the controller and the audio bytes in the speaker's
/// format.
public struct LocalServiceRPCSpeakerArguments: Codable, Sendable {
  /// The controller whose speaker plays.
  public let controller: ControllerReference
  /// The encoded audio.
  public let audio: Data

  /// Creates the arguments from a controller and its audio.
  public init(controller: ControllerReference, audio: Data) {
    self.controller = controller
    self.audio = audio
  }
}
/// The arguments that set the color of a controller.
public struct LocalServiceRPCColorArguments: Codable, Sendable {
  /// The controller whose color changes.
  public let controller: ControllerReference
  /// The red component, from 0 to 255.
  public let red: Int
  /// The green component, from 0 to 255.
  public let green: Int
  /// The blue component, from 0 to 255.
  public let blue: Int

  /// Creates the arguments from a controller and a color.
  public init(
    controller: ControllerReference,
    red: Int,
    green: Int,
    blue: Int
  ) {
    self.controller = controller
    self.red = red
    self.green = green
    self.blue = blue
  }
}
/// The arguments of `previewPhysicalColor`.
public struct LocalServiceRPCColorPreviewArguments: Codable, Sendable {
  /// The controller whose color is previewed.
  public let controller: ControllerReference
  /// The token that holds the preview.
  public let token: UUID
  /// The red component, from 0 to 255.
  public let red: Int
  /// The green component, from 0 to 255.
  public let green: Int
  /// The blue component, from 0 to 255.
  public let blue: Int

  /// Creates the arguments from a controller, a token and a color.
  public init(
    controller: ControllerReference,
    token: UUID,
    red: Int,
    green: Int,
    blue: Int
  ) {
    self.controller = controller
    self.token = token
    self.red = red
    self.green = green
    self.blue = blue
  }
}
/// The arguments of `releasePhysicalColorPreview`.
public struct LocalServiceRPCColorPreviewReleaseArguments: Codable, Sendable {
  /// The controller whose preview ends.
  public let controller: ControllerReference
  /// The token that holds the preview.
  public let token: UUID

  /// Creates the arguments from a controller and a token.
  public init(controller: ControllerReference, token: UUID) {
    self.controller = controller
    self.token = token
  }
}

/// What a call reports when the server ends the connection without a reply.
package enum LocalServiceRPCClosedWithoutReply: Sendable {
  /// The server turned this process away.
  case peerRejected
  /// The server, which had accepted this process, ended the connection.
  case serviceClosedConnection

  /// The error that ``LocalServiceRPCTransport`` throws for this case.
  var error: LocalServiceRPCError {
    switch self {
    case .peerRejected: return .peerRejected
    case .serviceClosedConnection: return .serviceClosedConnection
    }
  }
}

/// The failures of a local RPC call or of the local RPC server.
package enum LocalServiceRPCError: Error, Equatable, LocalizedError, Sendable {
  /// The server is already running.
  case alreadyRunning
  /// A socket call failed; the value is its error number.
  case connectionFailed(Int32)
  /// A frame is malformed or larger than the transport allows.
  case invalidFrame
  /// The server turned this process away.
  case peerRejected
  /// The service replied with the error message in the value.
  case remote(String)
  /// The server, which had accepted this process, ended the connection.
  case serviceClosedConnection
  /// The service is stopping, so the server cannot start again.
  case stopping
  /// No reply arrived before the deadline.
  case timeout

  /// The description of the error for the user.
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
    case .serviceClosedConnection: return "The main application closed the connection."
    case .stopping: return "The main application is stopping."
    case .timeout: return "Main application RPC timed out."
    }
  }
}
/// The framing and socket helpers of the local RPC.
///
/// A frame is a 4-byte big-endian length followed by that many bytes of JSON.
package enum LocalServiceRPCTransport {
  /// The largest frame the transport sends or receives, in bytes.
  static let maximumFrameBytes = ApplicationServiceRemappingRPC.maximumTransportFrameBytes
  /// The path of the service's per-user RPC socket.
  package static var defaultSocketPath: String { socketPath(in: MacOSDataDirectory()) }

  /// The per-user RPC socket in the shared temp location of `dataDirectory`.
  static func socketPath(in dataDirectory: any DataDirectory) -> String {
    dataDirectory.fileURL("com.openjoystickdriver.\(geteuid()).rpc", in: .sharedTemporary).path
  }

  /// Opens a Unix socket to the server at `socketPath`, with the send and receive timeout
  /// `timeoutSeconds`.
  ///
  /// - Throws: ``LocalServiceRPCError/connectionFailed(_:)`` with the error number of the failed
  ///   call.
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

  /// The Unix socket address for `path`.
  ///
  /// - Throws: ``LocalServiceRPCError/invalidFrame`` when `path` does not fit in a socket address.
  package static func socketAddress(path: String) throws -> sockaddr_un {
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

  /// The byte length of the socket address for `path`.
  package static func socketAddressLength(path: String) -> socklen_t {
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path) ?? 0
    return socklen_t(pathOffset + path.utf8.count + 1)
  }

  /// Sets the send and receive timeout of `descriptor`; a value below 0.1 s becomes 0.1 s.
  ///
  /// - Throws: ``LocalServiceRPCError/connectionFailed(_:)`` when a socket option fails.
  package static func setTimeout(_ descriptor: Int32, seconds: TimeInterval) throws {
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

  /// Sends `data` as one frame.
  ///
  /// - Throws: ``LocalServiceRPCError/invalidFrame`` when `data` is larger than the frame limit,
  ///   and ``LocalServiceRPCError/connectionFailed(_:)`` when the send fails.
  static func sendFrame(_ data: Data, to descriptor: Int32) throws {
    guard data.count <= maximumFrameBytes else { throw LocalServiceRPCError.invalidFrame }
    var length = UInt32(data.count).bigEndian
    try withUnsafeBytes(of: &length) { try sendAll($0, to: descriptor) }
    try data.withUnsafeBytes { try sendAll($0, to: descriptor) }
  }

  /// Reads one frame.
  ///
  /// `closedBeforeFrameError` is thrown when the peer closes before it sends any byte.
  ///
  /// - Throws: ``LocalServiceRPCError/timeout`` when the read times out, and
  ///   ``LocalServiceRPCError/invalidFrame`` for a frame that is cut short or larger than the frame
  ///   limit.
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

  /// Sends all of `bytes`, repeating the send until none is left.
  ///
  /// - Throws: ``LocalServiceRPCError/connectionFailed(_:)`` when a send fails.
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

  /// Fills `bytes` from `descriptor`.
  ///
  /// - Throws: ``LocalServiceRPCError/timeout`` when the read times out,
  ///   `closedBeforeAnyBytesError` when the peer closes before the first byte, and
  ///   ``LocalServiceRPCError/invalidFrame`` when it closes later.
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

/// The client side of the local RPC; its methods are in extensions.
public enum LocalServiceRPCClient {}
