import Foundation

/// Seconds an RPC call waits for the service's reply unless the call sets its own deadline.
let applicationServiceDefaultReplyTimeoutSeconds: TimeInterval = 5

/// The failures of a call through ``ApplicationServiceClient`` that happen before the service
/// answers.
public enum ApplicationServiceClientError: Error, LocalizedError, Sendable {
  /// The client has not found the service's local server.
  case notConnected
  /// The service did not reply before the call's deadline.
  case timeout
  /// The reply does not decode as the payload the call expects.
  case invalidResponse

  /// The description of the error for the user.
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
  /// Guards `connected` and `unansweredProbes`.
  let stateLock = NSLock()
  /// The path of the service's local socket.
  let socketPath: String
  /// Seconds a call waits for the service's reply unless the call sets its own deadline.
  package let replyTimeoutSeconds: TimeInterval
  /// Whether a probe found the service's local server and no disconnect followed.
  var connected = false
  /// The probes of the local server that found no answer, across all `connect` calls.
  var unansweredProbes = 0

  /// How many probes of the local server found no answer, across all `connect` calls.
  package var unansweredProbeCount: Int { stateLock.withLock { unansweredProbes } }

  /// Creates a client for the service's default local socket.
  public init() {
    socketPath = LocalServiceRPCTransport.defaultSocketPath
    replyTimeoutSeconds = applicationServiceDefaultReplyTimeoutSeconds
  }

  /// Creates a client for the service socket at `socketPath`.
  ///
  /// A call waits for a reply for `requestTimeoutSeconds`, or for the default reply limit when
  /// that is longer.
  package init(socketPath: String, requestTimeoutSeconds: TimeInterval = 0) {
    self.socketPath = socketPath
    replyTimeoutSeconds = max(requestTimeoutSeconds, applicationServiceDefaultReplyTimeoutSeconds)
  }
}
