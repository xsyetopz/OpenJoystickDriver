import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ProfileRecoverCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "recover",
    abstract: CLILocalized.text(
      "cli.profile.recover.abstract",
      "Remove damaged profile files and reset a damaged active profile list."
    ),
    discussion: CLILocalized.text(
      "cli.profile.recover.discussion",
      "Acts on each issue that 'ojd profile list' reports. The service first backs up each file "
        + "beside the original, under a name that contains .backup-. Asks for confirmation on a "
        + "terminal; needs --force otherwise."
    )
  )

  /// The `--json` result. `recovered` names each issue the command acted on.
  struct Result: Encodable, Equatable {
    let recovered: [ProfileListCommand.Result.Issue]
    let dryRun: Bool
  }

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run", "Print what would change, and change nothing.")
    )
  )
  var dryRun = false

  @OptionGroup
  var global: GlobalOptions

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
            "cli.profile.recover.confirm",
            "Remove the damaged profile files and reset a damaged active profile list?"
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
            message: $0.message
          )
        },
        dryRun: dryRun
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain(result.recovered.map { [$0.id, $0.kind] })
      case .human:
        if issues.isEmpty {
          CLIOutput.stdout(
            CLILocalized.text("cli.profile.recover.none", "No damaged profile files.")
          )
        }
        for issue in issues { Self.printAction(issue, dryRun: dryRun) }
      }
    }
  }

  private static func printAction(_ issue: ApplicationServiceRemappingProfileIssue, dryRun: Bool) {
    let id = issue.id.uuidString
    switch (issue.kind, dryRun) {
    case (.damagedProfile, true):
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.profile.recover.remove.dry_run",
          "Would remove the damaged profile file of issue %@.",
          id
        )
      )
    case (.damagedProfile, false):
      CLIOutput.success(
        CLILocalized.format(
          "cli.profile.recover.remove.done",
          "Removed the damaged profile file of issue %@.",
          id
        )
      )
    case (.unusableLibrary, true):
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.profile.recover.reset.dry_run",
          "Would reset the active profile list."
        )
      )
    case (.unusableLibrary, false):
      CLIOutput.success(
        CLILocalized.text("cli.profile.recover.reset.done", "Reset the active profile list.")
      )
    }
  }
}
