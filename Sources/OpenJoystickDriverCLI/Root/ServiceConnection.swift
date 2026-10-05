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
    let client = try await open()
    defer { client.disconnect() }
    return try await withDeadline(seconds: timeout) { try await body(client) }
  }

  /// Connects to a running service for a command that sends many requests, such as a stream.
  ///
  /// The caller disconnects the client and bounds each request with `withDeadline`.
  static func open() async throws -> ApplicationServiceClient {
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect(timeoutSeconds: 0)
    guard client.isConnected else { throw CLIFailure.serviceUnavailable }
    return client
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
    case let rejection as ApplicationServiceRemappingRPCError
    where rejection.code == .duplicateName:
      CLIFailure(
        rejection.code.errorCode,
        CLILocalized.text(
          "cli.error.duplicate_profile_name",
          "A profile with that name already exists. 'ojd profile list' shows every profile."
        )
      )
    case let rejection as ApplicationServiceRemappingRPCError:
      CLIFailure.serviceRequestFailed(rejection.localizedDescription, id: rejection.code.errorCode)
    default: CLIFailure.serviceRequestFailed(error.localizedDescription)
    }
  }
}

extension CLIFailure {
  static func timedOut(seconds: Double?) -> Self {
    guard let seconds else {
      return Self(
        .serviceTimeout,
        CLILocalized.text(
          "cli.error.service_timeout",
          "The service did not reply in time. Retry, or check it with 'ojd status'."
        )
      )
    }
    return Self(
      .serviceTimeout,
      CLILocalized.format(
        "cli.error.request_timeout",
        "The service did not reply within %@. Retry with a larger --timeout.",
        seconds.durationText
      )
    )
  }

  static var peerRejected: Self {
    Self(
      .peerRejected,
      CLILocalized.text(
        "cli.error.peer_rejected",
        "The service rejected this ojd, because it is not signed like the app. "
          + "Run the ojd that ships inside OpenJoystickDriver.app."
      )
    )
  }
}

extension Double {
  /// Seconds as a localized value with a unit symbol, such as `0.5s` or `5 с`. A symbol needs
  /// no plural agreement, so messages read correctly for any value.
  var durationText: String { durationText(locale: .current) }

  func durationText(locale: Locale) -> String {
    Measurement(value: self, unit: UnitDuration.seconds)
      .formatted(.measurement(width: .narrow, numberFormatStyle: .number).locale(locale))
  }
}
