import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd profile activate` command: applies a profile, replacing the active profile of the same
/// controller model and app scope.
struct ProfileActivateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "cli.profile.activate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.activate.discussion"
    )
  )

  /// The profile to activate.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// `--allow-empty`: activate a profile that produces no output.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.activate.allowEmpty"
      )
    )
  )
  var allowEmpty = false

  /// `--confirm-actions`: allow the profile to open applications and URLs, run shortcuts and type
  /// text.
  @Flag(help: ArgumentHelp(CLILocalized.text("cli.profile.activate.confirmActions")))
  var confirmActions = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, allowEmpty, confirmActions) = (profile, allowEmpty, confirmActions)
      let (target, before, after) = try await ServiceConnection.request { client in
        let (target, before) = try await selector.resolve(with: client)
        guard allowEmpty || !target.producesNoOutput else {
          throw CLIFailure.usage(
            CLILocalized.text(
              "cli.profile.activate.empty"
            )
          )
        }
        let preflight = RemappingActivationPreflight(
          profile: target,
          postEventAccess: before.postEventAccess
        )
        if let missing = preflight.missingPermissionsText { CLIOutput.stderr(missing) }
        guard confirmActions || !preflight.needsConfirmation else {
          throw CLIFailure.usage(
            CLILocalized.format(
              "cli.profile.activate.actionsNeedConfirmation",
              preflight.launchedActions.joined(separator: "\n")
            )
          )
        }
        let after = try await client.activateRemappingProfile(id: target.id, allowEmpty: allowEmpty)
        return (target, before, after)
      }
      let wasActive = ProfileSummary(target, snapshot: before).active
      try printProfile(
        ProfileResult(profile: try savedSummary(target.id, in: after), changed: !wasActive),
        message: CLILocalized.format(
          "cli.profile.activate.done",
          target.name,
          ProfileSummary(target, snapshot: after).controller
        )
      )
    }
  }
}

/// The `ojd profile deactivate` command: stops applying a profile, so the controller sends its own
/// input.
struct ProfileDeactivateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.profile.deactivate.abstract"
    )
  )

  /// The profile to deactivate.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = profile
      let (target, before, after) = try await ServiceConnection.request { client in
        let (target, before) = try await selector.resolve(with: client)
        return (target, before, try await client.deactivateRemappingProfile(profileID: target.id))
      }
      let wasActive = ProfileSummary(target, snapshot: before).active
      try printProfile(
        ProfileResult(profile: try savedSummary(target.id, in: after), changed: wasActive),
        message: CLILocalized.format(
          "cli.profile.deactivate.done",
          target.name
        )
      )
    }
  }
}
