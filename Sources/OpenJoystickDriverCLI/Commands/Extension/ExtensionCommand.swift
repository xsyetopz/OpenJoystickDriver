import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct ExtensionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "extension",
    abstract: CLILocalized.text(
      "cli.extension.abstract"
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
    detail = status.detail
  }
}

struct ExtensionStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: CLILocalized.text(
      "cli.extension.status.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.extension.status.discussion"
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
            report.bundle.rawValue
          )
        )
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.extension.status.registration",
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
        "cli.extension.timeout"
      )
    )
  case .failed:
    throw CLIFailure(
      .systemRequestFailed,
      CLILocalized.text(
        "cli.extension.submit_failed"
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
          "cli.extension.approval"
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
      "cli.extension.activate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.extension.activate.discussion"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .activate,
        done: .active,
        message: CLILocalized.text("cli.extension.activated")
      )
    }
  }
}

struct ExtensionDeactivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.extension.deactivate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.extension.deactivate.discussion"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      try await submit(
        .deactivate,
        done: .inactive,
        message: CLILocalized.text("cli.extension.deactivated")
      )
    }
  }
}
