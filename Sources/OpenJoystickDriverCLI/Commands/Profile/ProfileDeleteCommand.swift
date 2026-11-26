import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile delete` command: deletes a profile, which stops applying if it is active.
struct ProfileDeleteCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "delete",
    abstract: CLILocalized.text("cli.profile.delete.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.delete.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The profile that the command deletes.
    let deleted: ProfileSummary
    /// Whether `--dry-run` is set, so nothing is deleted.
    let dryRun: Bool
  }

  /// The profile to delete.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// `-f`, `--force`: skip the confirmation.
  @OptionGroup
  var force: ForceFlag

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @OptionGroup
  var dryRun: DryRunFlag

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = profile
      let client = try await ServiceConnection.open()
      defer { client.disconnect() }
      let timeout = CLIContext.current.requestTimeout
      let (target, snapshot) = try await ServiceConnection.withDeadline(seconds: timeout) {
        try await selector.resolve(with: client)
      }
      let summary = ProfileSummary(target, snapshot: snapshot)
      if !dryRun.isSet {
        try CLITerminal.confirm(
          CLILocalized.format(
            "cli.profile.delete.confirm",
            target.name
          ),
          force: force.isSet
        )
        _ = try await ServiceConnection.withDeadline(seconds: timeout) {
          try await client.deleteRemappingProfile(id: target.id)
        }
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIStatus(details: Result(deleted: summary, dryRun: dryRun.isSet)))
      case .plain: CLIOutput.plain([summary.row])
      case .human:
        if dryRun.isSet {
          CLIOutput.stdout(
            CLILocalized.format(
              "cli.profile.delete.dryRun",
              target.name
            )
          )
        } else {
          CLIOutput.success(
            CLILocalized.format("cli.profile.delete.done", target.name)
          )
        }
      }
    }
  }
}
