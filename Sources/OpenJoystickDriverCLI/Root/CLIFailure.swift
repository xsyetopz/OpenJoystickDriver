import Foundation
import OpenJoystickDriverKit

/// The exit codes `ojd` documents in its root help and the command-line docs.
enum CLIExitCode: Int32, Sendable {
  case success = 0
  case failure = 1
  case usage = 64
  case serviceUnavailable = 69
  case permissionDenied = 77
  /// The `ojd` of a repository build could not hand the command to the installed app.
  case installedCLIFailed = 127
  case interrupted = 130

  /// The exit code of the failure that `id` names; `Resources/ErrorCodes.json` lists it as
  /// `exitCode`. A code of another area, such as a remapping code, is a plain failure.
  init(for id: ErrorCode) {
    switch id {
    case .unknownCommand, .usage, .confirmationRequired: self = .usage
    case .serviceUnavailable: self = .serviceUnavailable
    case .permissionMissing: self = .permissionDenied
    case .installedCLIFailed: self = .installedCLIFailed
    default: self = .failure
    }
  }
}

/// An expected failure that `ojd` reports as `ojd: <code>: <message>` on stderr.
///
/// `id` is the stable error code, and the exit code follows from it. `message` states what
/// failed and how to fix it, already localized.
struct CLIFailure: Error, Equatable, Sendable {
  let id: ErrorCode
  let message: String

  var code: CLIExitCode { CLIExitCode(for: id) }

  /// The line `ojd` writes on stderr.
  var line: String { "ojd: \(id.rawValue): \(message)" }

  init(_ id: ErrorCode, _ message: String) {
    self.id = id
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

  /// The service did not complete a request; `id` is the service's own code when it sent one.
  static func serviceRequestFailed(_ detail: String, id: ErrorCode = .serviceRequestFailed) -> Self
  {
    Self(
      id,
      CLILocalized.format(
        "cli.error.service_request_failed",
        "The service did not complete the request: %@. Check it with 'ojd status'.",
        // The service's message ends with a period; the format adds its own.
        detail.hasSuffix(".") ? String(detail.dropLast()) : detail
      )
    )
  }

  /// A macOS permission that `permissionName` names is missing; exit code 77.
  static func permissionMissing(_ permissionName: String) -> Self {
    Self(
      .permissionMissing,
      CLILocalized.format(
        "cli.error.permission_missing",
        "%@ access is missing. Grant it with 'ojd permission request'.",
        permissionName
      )
    )
  }

  static func usage(_ message: String) -> Self { Self(.usage, message) }
}
