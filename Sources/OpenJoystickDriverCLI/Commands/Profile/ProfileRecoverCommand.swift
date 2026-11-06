import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile recover` command: repairs the problems that `profile list` reports.
///
/// It removes a damaged profile file and resets an unusable profile library. The service backs up
/// each file first.
struct ProfileRecoverCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "recover",
    abstract: CLILocalized.text(
      "cli.profile.recover.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.recover.discussion"
    )
  )

  /// The `--json` result. `recovered` names each issue the command acted on.
  struct Result: Encodable, Equatable {
    /// The issues the command acted on.
    let recovered: [ProfileListCommand.Result.Issue]
    /// Whether `--dry-run` is set, so nothing changes.
    let dryRun: Bool
  }

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.dryRun")
    )
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      let issues = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await client.getRemappingSnapshot()
      }.profileIssues
      if !dryRun, !issues.isEmpty {
        try CLITerminal.confirm(
          CLILocalized.text(
            "cli.profile.recover.confirm"
          ),
          force: force
        )
        for issue in issues {
          _ = try await ServiceConnection.withDeadline(seconds: timeout) {
            switch issue.kind {
            case .damagedProfile: try await client.deleteDamagedRemappingProfile(issueID: issue.id)
            case .unusableLibrary: try await client.resetRemappingProfileLibrary(issueID: issue.id)
            }
          }
        }
      }
      let result = Result(
        recovered: issues.map {
          ProfileListCommand.Result.Issue(
            id: $0.id.uuidString,
            kind: $0.kind.rawValue,
            code: $0.code.rawValue,
            message: $0.message
          )
        },
        dryRun: dryRun
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: result))
      case .plain: CLIOutput.plain(result.recovered.map { [$0.id, $0.kind] })
      case .human:
        if issues.isEmpty {
          CLIOutput.stdout(
            CLILocalized.text("cli.profile.recover.none")
          )
        }
        for issue in issues { Self.printAction(issue, dryRun: dryRun) }
      }
    }
  }

  /// Prints what the command does, or would do with `--dry-run`, for `issue`.
  private static func printAction(_ issue: ApplicationServiceRemappingProfileIssue, dryRun: Bool) {
    let id = issue.id.uuidString
    switch (issue.kind, dryRun) {
    case (.damagedProfile, true):
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.profile.recover.removeDryRun",
          id
        )
      )
    case (.damagedProfile, false):
      CLIOutput.success(
        CLILocalized.format(
          "cli.profile.recover.removeDone",
          id
        )
      )
    case (.unusableLibrary, true):
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.profile.recover.resetDryRun"
        )
      )
    case (.unusableLibrary, false):
      CLIOutput.success(
        CLILocalized.text("cli.profile.recover.resetDone")
      )
    }
  }
}
