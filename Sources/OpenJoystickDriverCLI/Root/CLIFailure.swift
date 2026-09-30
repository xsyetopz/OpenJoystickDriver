import Foundation

/// The exit codes `ojd` documents in its root help and the command-line docs.
enum CLIExitCode: Int32, Sendable {
  case success = 0
  case failure = 1
  case usage = 64
  case serviceUnavailable = 69
  case permissionDenied = 77
  case interrupted = 130
}

/// An expected failure that `ojd` reports as `ojd: <message>` on stderr.
///
/// `message` states what failed and how to fix it, already localized.
struct CLIFailure: Error, Equatable, Sendable {
  let code: CLIExitCode
  let message: String

  init(_ code: CLIExitCode = .failure, _ message: String) {
    self.code = code
    self.message = message
  }

  static var serviceUnavailable: Self {
    Self(
      .serviceUnavailable,
      CLILocalized.text(
        "cli.error.service_unavailable",
        "The OpenJoystickDriver service is not running. Start it with 'ojd service start'."
      )
    )
  }

  static func serviceRequestFailed(_ detail: String) -> Self {
    Self(
      .failure,
      CLILocalized.format(
        "cli.error.service_request_failed",
        "The service did not complete the request: %@. Check it with 'ojd status'.",
        detail
      )
    )
  }

  static func usage(_ message: String) -> Self { Self(.usage, message) }
}
