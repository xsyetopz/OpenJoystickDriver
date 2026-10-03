import Foundation

let applicationServiceDefaultReplyTimeoutSeconds: TimeInterval = 5

public enum ApplicationServiceClientError: Error, LocalizedError, Sendable {
  case notConnected
  case timeout
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Not connected to main application."
    case .timeout: return "Main application did not respond before the deadline."
    case .invalidResponse: return "Main application returned an invalid response."
    }
  }
}

/// The internal RPC client that OpenJoystickDriver's own app and `ojd` use to call the service.
///
/// The service accepts a connection only from a process with the same signing identifier and
/// team ID as the service, so only OpenJoystickDriver's own signed executables can connect.
/// Other programs use the `ojd` command and its `--json` output instead.
/// The methods and payloads can change in any release.
public final class ApplicationServiceClient: @unchecked Sendable {
  let stateLock = NSLock()
  let socketPath: String
  var connected = false

  public init() { socketPath = LocalServiceRPCTransport.defaultSocketPath }

  package init(socketPath: String) { self.socketPath = socketPath }
}
