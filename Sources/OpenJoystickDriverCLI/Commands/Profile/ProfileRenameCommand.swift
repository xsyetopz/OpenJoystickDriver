import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile rename` command: gives a profile another name of 1 to 80 characters.
struct ProfileRenameCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "rename",
    abstract: CLILocalized.text("cli.profile.rename.abstract")
  )

  /// The profile to rename.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The name to give.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.rename.name"),
      valueName: "new-name"
    )
  )
  var name: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, newName) = (profile, name)
      let (renamed, snapshot) = try await ServiceConnection.request { client in
        let (current, _) = try await selector.resolve(with: client)
        let renamed = try current.replacing(name: newName).validatedForCLI()
        return (renamed, try await client.updateRemappingProfile(renamed, expectedCurrent: current))
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(renamed.id, in: snapshot), changed: true),
        message: CLILocalized.format("cli.profile.rename.done", renamed.name)
      )
    }
  }
}
