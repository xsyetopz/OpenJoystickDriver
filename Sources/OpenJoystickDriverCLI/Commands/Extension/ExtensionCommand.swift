import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct ExtensionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "extension",
    abstract: CLILocalized.text(
      "cli.extension.abstract",
      "Show, activate, or deactivate the OpenJoystickDriver DriverKit system extension."
    ),
    subcommands: [
      ExtensionStatusCommand.self, ExtensionActivateCommand.self, ExtensionDeactivateCommand.self,
    ]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// The `ojd extension status --json` result.
///
/// `detail` is the `systemextensionsctl` record, the unexpected bundle identifier, or the
/// reason the state is unavailable; it is absent when there is nothing to add.
struct ExtensionStatusReport: Encodable, Equatable {
  let bundle: StatusReport.Extension.Bundle
  let registration: StatusReport.Extension.Registration
  let detail: String?

  init(_ status: ExtensionStatus) {
    let summary = StatusReport.Extension(status)
    bundle = summary.bundle
    registration = summary.registration
    switch (status.bundle, status.registration) {
    case (_, .active(let record)), (_, .inactive(let record)): detail = record
    case (_, .unavailable(let reason)): detail = reason
    case (.invalid(let identifier), _): detail = identifier
    default: detail = nil
    }
  }
}

struct ExtensionStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.extension.status.abstract",
      "Show whether the extension is in the app and registered with macOS."
    ),
    discussion: CLILocalized.text(
      "cli.extension.status.discussion",
      "Bundle is present, missing, or invalid. Registration is active, inactive, absent, or "
        + "unavailable; unavailable exits 1. Works when the service is stopped."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let status = StatusCommand.extensionProbe()
      let report = ExtensionStatusReport(status)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain([
          ["bundle", report.bundle.rawValue], ["registration", report.registration.rawValue],
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.extension.status.bundle",
            "Embedded extension:  %@",
            report.bundle.rawValue
          )
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.extension.status.registration",
            "macOS registration:  %@",
            report.registration.rawValue
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
            "cli.extension.status.unavailable",
            "macOS did not report the extension registration: %@. "
              + "Retry, or run 'systemextensionsctl list'.",
            reason
          )
        )
      }
    }
  }
}

/// The `--json` result of `extension activate` and `extension deactivate`.
struct ExtensionResult: Encodable, Equatable {
  enum State: String, Encodable {
    case active
    case inactive
    case awaitingApproval = "awaiting-approval"
  }

  let state: State
}

private func submit(
  _ action: ExtensionSubmission.Action,
  done state: ExtensionResult.State,
  message: String
) async throws {
  let outcome = try await ExtensionSubmission.submit(action)
  let result: ExtensionResult.State
  switch outcome {
  case .active, .inactive: result = state
  case .awaitingApproval: result = .awaitingApproval
  case .cancelled: throw CancellationError()
  case .timedOut:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "cli.extension.timeout",
        "macOS did not finish the request in time. "
          + "Check System Settings for an approval prompt, then run 'ojd extension status'."
      )
    )
  case .failed:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "cli.extension.submit_failed",
        "macOS rejected the request. Run 'ojd extension status' and check "
          + "'systemextensionsctl list'."
      )
    )
  }
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(ExtensionResult(state: result))
  case .plain: CLIOutput.plain([["state", result.rawValue]])
  case .human:
    if result == .awaitingApproval {
      CLIOutput.stderr(
        CLILocalized.text(
          "cli.extension.approval",
          "The request needs your approval. Allow it in System Settings > General > "
            + "Login Items & Extensions > Driver Extensions."
        )
      )
    } else {
      CLIOutput.success(message)
    }
  }
}

struct ExtensionActivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "cli.extension.activate.abstract",
      "Ask macOS to activate the extension. It may need approval in System Settings."
    ),
    discussion: CLILocalized.text(
      "cli.extension.activate.discussion",
      "Run the ojd inside /Applications/OpenJoystickDriver.app. Waiting for approval exits 0."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .activate,
        done: .active,
        message: CLILocalized.text("cli.extension.activated", "The extension is active.")
      )
    }
  }
}

struct ExtensionDeactivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.extension.deactivate.abstract",
      "Ask macOS to deactivate the extension. Controllers return to macOS."
    ),
    discussion: CLILocalized.text(
      "cli.extension.deactivate.discussion",
      "Run the ojd inside /Applications/OpenJoystickDriver.app."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .deactivate,
        done: .inactive,
        message: CLILocalized.text("cli.extension.deactivated", "The extension is inactive.")
      )
    }
  }
}
