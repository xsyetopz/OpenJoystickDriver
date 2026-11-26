import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile duplicate` command: copies a profile under another name.
///
/// The copy is inactive.
struct ProfileDuplicateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "duplicate",
    abstract: CLILocalized.text(
      "cli.profile.duplicate.abstract"
    )
  )

  /// The profile to copy.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The name of the copy.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.duplicate.name"),
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
      let (copy, snapshot) = try await ServiceConnection.request { client in
        let (original, _) = try await selector.resolve(with: client)
        let copy = try original.copy(id: UUID(), name: newName).validatedForCLI()
        return (copy, try await client.createRemappingProfile(copy))
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(copy.id, in: snapshot), changed: true),
        message: CLILocalized.format(
          "cli.profile.duplicate.done",
          copy.name,
          copy.id.uuidString
        )
      )
    }
  }
}
