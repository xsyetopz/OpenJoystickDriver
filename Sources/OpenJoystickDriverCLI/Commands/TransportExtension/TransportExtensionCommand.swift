import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd transport-extension` command group: shows, activates and deactivates the DriverKit
/// transport extension.
struct TransportExtensionCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "transport-extension",
    abstract: CLILocalized.text(
      "platform.macos.cli.transportExtension.group.abstract"
    ),
    subcommands: [
      TransportExtensionStatusCommand.self, TransportExtensionActivateCommand.self,
      TransportExtensionDeactivateCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd transport-extension status --json` result.
///
/// `detail` is the `systemextensionsctl` record, the unexpected bundle identifier, or the reason
/// the state is unavailable; it is absent when there is nothing to add.
struct TransportExtensionStatusReport: Encodable, Equatable {
  /// Whether the extension is in the app bundle.
  let bundle: StatusReport.Extension.Bundle
  /// Whether macOS has the extension registered.
  let registration: StatusReport.Extension.Registration
  /// Extra text about the registration, when there is any.
  let detail: String?

  /// Creates the report from the extension status.
  init(_ status: ExtensionStatus) {
    let summary = StatusReport.Extension(status)
    bundle = summary.bundle
    registration = summary.registration
    detail = status.detail
  }
}

/// The `ojd transport-extension status` command: prints the bundle and registration state of the
/// extension.
///
/// It fails with `systemRequestFailed` after the output when macOS cannot report the registration.
struct TransportExtensionStatusCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "platform.macos.cli.transportExtension.status.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transportExtension.status.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let status = StatusCommand.extensionProbe()
      let report = TransportExtensionStatusReport(status)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain([
          ["bundle", CommandLineName.kebab(report.bundle.rawValue)],
          ["registration", CommandLineName.kebab(report.registration.rawValue)],
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.transportExtension.status.bundle",
            CommandLineName.kebab(report.bundle.rawValue)
          )
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "platform.macos.cli.transportExtension.status.registration",
            CommandLineName.kebab(report.registration.rawValue)
          )
        )
        if let detail = report.detail, report.registration != .unavailable {
          CLIOutput.stdout(detail)
        }
      }
      if case .unavailable(let reason) = status.registration {
        throw CLIFailure(
          .systemRequestFailed,
          CLILocalized.format(
            "platform.macos.cli.transportExtension.status.unavailable",
            reason
          )
        )
      }
    }
  }
}

/// The `--json` result of `transport-extension activate` and `transport-extension deactivate`.
struct TransportExtensionResult: Encodable, Equatable {
  /// The state after the request.
  enum State: String, Encodable {
    /// The extension is active.
    case active = "Active"
    /// The extension is inactive.
    case inactive = "Inactive"
    /// macOS waits for the user to approve the extension.
    case awaitingApproval = "AwaitingApproval"
  }

  /// The state after the request.
  let state: State
}

/// Submits `action`, then prints the state it reached.
///
/// `done` is the state to report when macOS finishes the request, and `message` is the success line
/// for it. An approval that macOS still waits for prints the approval hint on stderr instead.
///
/// - Throws: ``CancellationError`` when the request is cancelled, and ``CLIFailure`` with
///   `systemRequestFailed` when the request times out or fails.
func submitTransportExtension(
  _ action: TransportExtensionSubmission.Action,
  done state: TransportExtensionResult.State,
  message: String
) async throws {
  let outcome = try await TransportExtensionSubmission.submit(action)
  let result: TransportExtensionResult.State
  switch outcome {
  case .active, .inactive: result = state
  case .awaitingApproval: result = .awaitingApproval
  case .cancelled: throw CancellationError()
  case .timedOut:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "platform.macos.cli.transportExtension.group.timeout"
      )
    )
  case .failed:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "platform.macos.cli.transportExtension.group.submitFailed"
      )
    )
  }
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(TransportExtensionResult(state: result))
  case .plain: CLIOutput.plain([["state", CommandLineName.kebab(result.rawValue)]])
  case .human:
    if result == .awaitingApproval {
      CLIOutput.stderr(
        CLILocalized.text(
          "platform.macos.cli.transportExtension.group.approval"
        )
      )
    } else {
      CLIOutput.success(message)
    }
  }
}

/// The `ojd transport-extension activate` command: asks macOS to activate the extension in the app
/// bundle.
struct TransportExtensionActivateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "platform.macos.cli.transportExtension.activate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transportExtension.activate.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await submitTransportExtension(
        .activate,
        done: .active,
        message: CLILocalized.text("cli.transportExtension.group.activated")
      )
    }
  }
}

/// The `ojd transport-extension deactivate` command: asks macOS to deactivate the extension.
struct TransportExtensionDeactivateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "platform.macos.cli.transportExtension.deactivate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.transportExtension.deactivate.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await submitTransportExtension(
        .deactivate,
        done: .inactive,
        message: CLILocalized.text("cli.transportExtension.group.deactivated")
      )
    }
  }
}
