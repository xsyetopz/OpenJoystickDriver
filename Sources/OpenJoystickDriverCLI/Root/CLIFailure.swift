import Foundation
import OpenJoystickDriverKit

/// The exit codes `ojd` documents in its root help and the command-line docs.
enum CLIExitCode: Int32, Sendable {
  /// The command succeeded.
  case success = 0
  /// The command failed.
  case failure = 1
  /// The command line is wrong.
  case usage = 64
  /// The service is not running or did not answer.
  case serviceUnavailable = 69
  /// A macOS permission is missing.
  case permissionDenied = 77
  /// The `ojd` of a repository build could not hand the command to the installed app.
  case installedCLIFailed = 127
  /// The command is interrupted by SIGINT or cancelled.
  case interrupted = 130

  /// The exit code of the failure that `id` names.
  ///
  /// The exit status of `id` must be one of the cases; anything else stops the process.
  init(for id: ErrorCode) {
    guard let code = Self(rawValue: id.commandLineExitStatus) else {
      preconditionFailure("\(id.rawValue) has an exit status that CLIExitCode does not list.")
    }
    self = code
  }
}

/// An expected failure that `ojd` reports as `error[<code>]: <message>` on stderr.
///
/// `id` is the stable error code, and the exit code follows from it. `message` states what
/// failed and how to fix it, already localized.
typealias CLIFailure = CodedFailure

extension CLIFailure {
  /// The exit code that follows from ``id``.
  var code: CLIExitCode { CLIExitCode(for: id) }

  /// The line `ojd` writes on stderr.
  var line: String { Self.prefix(id) + message }

  /// The start of each error line of `ojd`, which names the stable code.
  static func prefix(_ id: ErrorCode) -> String { "error[\(id.rawValue)]: " }

  /// The service is not running; the exit code is 69.
  static var serviceUnavailable: Self {
    Self(
      .serviceUnavailable,
      CLILocalized.text(
        "cli.shared.error.serviceUnavailable"
      )
    )
  }

  /// The service did not complete a request; `id` is the service's own code when it sent one.
  static func serviceRequestFailed(_ detail: String, id: ErrorCode = .serviceRequestFailed) -> Self
  {
    Self(
      id,
      CLILocalized.format(
        "cli.shared.error.serviceRequestFailed",
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
        "cli.shared.error.permissionMissing",
        permissionName
      )
    )
  }
}
