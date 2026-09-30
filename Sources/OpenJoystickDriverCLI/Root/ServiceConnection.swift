import Foundation
import OpenJoystickDriverKit

/// The CLI's only route to the OpenJoystickDriver service.
///
/// No command starts the service implicitly: a request to a stopped service fails with exit
/// code 69, and `ojd service start` is the one command that launches it.
enum ServiceConnection {
  /// The service socket; tests point it at a private server.
  @TaskLocal
  static var socketPath = LocalServiceRPCTransport.defaultSocketPath

  /// The service's process identifier, or nil when nothing answers on the socket.
  static func processIdentifier() -> Int32? {
    LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath)
  }

  /// Connects to a running service and runs `body` within the `--timeout` request deadline.
  static func request<T: Sendable>(
    timeout: Double = CLIContext.current.requestTimeout,
    _ body: @escaping @Sendable (ApplicationServiceClient) async throws -> T
  ) async throws -> T {
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect(timeoutSeconds: 0)
    guard client.isConnected else { throw CLIFailure.serviceUnavailable }
    defer { client.disconnect() }
    return try await withDeadline(seconds: timeout) { try await body(client) }
  }

  /// Runs `operation` until it finishes or `seconds` elapse.
  ///
  /// Kit client errors become `CLIFailure` values; a missed deadline names `--timeout`.
  static func withDeadline<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let outcome = await withTimeout(seconds: seconds) { () async -> Result<T, any Error> in
      do { return .success(try await operation()) } catch { return .failure(error) }
    }
    switch outcome {
    case .success(let value): return value
    case .failure(let error): throw failure(for: error)
    case nil: throw CLIFailure.timedOut(seconds: seconds)
    }
  }

  static func failure(for error: any Error) -> any Error {
    switch error {
    case ApplicationServiceClientError.notConnected: CLIFailure.serviceUnavailable
    case ApplicationServiceClientError.timeout: CLIFailure.timedOut(seconds: nil)
    case LocalServiceRPCError.peerRejected: CLIFailure.peerRejected
    case is CLIFailure, is CancellationError: error
    default: CLIFailure.serviceRequestFailed(error.localizedDescription)
    }
  }
}

extension CLIFailure {
  static func timedOut(seconds: Double?) -> Self {
    guard let seconds else {
      return Self(
        .failure,
        CLILocalized.text(
          "cli.error.service_timeout",
          "The service did not reply in time. Retry, or check it with 'ojd status'."
        )
      )
    }
    return Self(
      .failure,
      CLILocalized.format(
        "cli.error.request_timeout",
        "The service did not reply within %@ seconds. Retry with a larger --timeout.",
        seconds.secondsText
      )
    )
  }

  static var peerRejected: Self {
    Self(
      .failure,
      CLILocalized.text(
        "cli.error.peer_rejected",
        "The service rejected this ojd, because it is not signed like the app. "
          + "Run the ojd that ships inside OpenJoystickDriver.app."
      )
    )
  }
}

extension Double {
  /// Seconds as short decimal text, such as `0.5` or `5`.
  var secondsText: String {
    self == rounded() && abs(self) < 1e15 ? String(Int(self)) : String(self)
  }
}
