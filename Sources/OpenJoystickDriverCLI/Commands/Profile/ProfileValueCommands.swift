public import ArgumentParser
import Foundation
import OpenJoystickDriverKit

extension ProfileKey: ExpressibleByArgument {}

/// The shared help of the `KEY` argument.
private let profileKeyHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.profile.group.key"
  ),
  valueName: "key"
)

/// The `ojd profile get` command: prints one value from a profile file.
///
/// A string prints alone, and any other value prints as JSON. A key with no value exits 1.
struct ProfileGetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.profile.get.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.get.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The key as typed.
    let key: String
    /// The value at the key.
    let value: ProfileValue
  }

  /// The profile to read.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The key of the value.
  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = profile
      let (document, _) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      guard let value = try ProfileValue(document).value(at: key.components[...]) else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.profile.get.missing",
            document.name,
            key.text
          )
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(key: key.text, value: value))
      case .plain, .human: CLIOutput.stdout(value.text)
      }
    }
  }
}

/// The `ojd profile set` command: changes one value in a profile file.
///
/// The value is read as JSON, or as a string when it is not JSON. The whole profile must stay
/// valid.
struct ProfileSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.profile.set.abstract"),
    discussion: CLILocalized.text(
      "cli.profile.set.discussion"
    ) + "\n\n" + CLILocalized.text("cli.profile.set.examples")
  )

  /// The profile to change.
  @Argument(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The key of the value.
  @Argument(help: profileKeyHelp)
  var key: ProfileKey

  /// The value as JSON text.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.profile.set.value"),
      valueName: "value"
    )
  )
  var value: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = profile
      let (current, snapshot) = try await ServiceConnection.request {
        try await selector.resolve(with: $0)
      }
      let edited = try ProfileSetting.change(current, key: key, to: ProfileValue(argument: value))
      guard edited != current else {
        try printProfile(
          ProfileResult(profile: ProfileSummary(current, snapshot: snapshot), changed: false),
          message: CLILocalized.text("cli.profile.edit.unchanged")
        )
        return
      }
      let after = try await ServiceConnection.request {
        try await $0.updateRemappingProfile(edited, expectedCurrent: current)
      }
      try printProfile(
        ProfileResult(profile: try savedSummary(edited.id, in: after), changed: true),
        message: CLILocalized.format(
          "cli.profile.set.done",
          key.text,
          edited.name
        )
      )
    }
  }
}
