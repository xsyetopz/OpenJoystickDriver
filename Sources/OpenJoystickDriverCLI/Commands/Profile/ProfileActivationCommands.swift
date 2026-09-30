import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ProfileActivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "cli.profile.activate.abstract",
      "Apply a profile to its controller model."
    ),
    discussion: CLILocalized.text(
      "cli.profile.activate.discussion",
      "The profile replaces the active profile of the same controller model and app scope. "
        + "A profile that turns off the virtual gamepad and has no bindings blocks all input "
        + "from the controller; activating one needs --allow-empty."
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.activate.allow_empty",
        "Activate the profile even when it blocks all controller input."
      )
    )
  )
  var allowEmpty = false

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (selector, allowEmpty) = (profile, allowEmpty)
      let (target, before, after) = try await ServiceConnection.request { client in
        let (target, before) = try await selector.resolve(with: client)
        guard allowEmpty || !target.suppressesAllControllerInput else {
          throw CLIFailure.usage(
            CLILocalized.text(
              "cli.profile.activate.empty",
              "This profile blocks all controller input. Add --allow-empty to activate it."
            )
          )
        }
        return (target, before, try await client.activateRemappingProfile(id: target.id))
      }
      let wasActive = ProfileSummary(target, snapshot: before).active
      try printProfile(
        ProfileResult(profile: try savedSummary(target.id, in: after), changed: !wasActive),
        message: CLILocalized.format(
          "cli.profile.activate.done",
          "Activated '%@' for %@.",
          target.name,
          ProfileSummary(target, snapshot: after).controller
        )
      )
    }
  }
}

struct ProfileDeactivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.profile.deactivate.abstract",
      "Stop applying a profile. The controller then sends its own input."
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup
  var global: GlobalOptions

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
          "Deactivated '%@'.",
          target.name
        )
      )
    }
  }
}
