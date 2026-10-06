import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ProfileActivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "activate",
    abstract: CLILocalized.text(
      "cli.profile.activate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.profile.activate.discussion"
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.profile.activate.allow_empty"
      )
    )
  )
  var allowEmpty = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (selector, allowEmpty) = (profile, allowEmpty)
      let (target, before, after) = try await ServiceConnection.request { client in
        let (target, before) = try await selector.resolve(with: client)
        guard allowEmpty || !target.producesNoOutput else {
          throw CLIFailure.usage(
            CLILocalized.text(
              "cli.profile.activate.empty"
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

struct ProfileDeactivateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "deactivate",
    abstract: CLILocalized.text(
      "cli.profile.deactivate.abstract"
    )
  )

  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
          target.name
        )
      )
    }
  }
}
