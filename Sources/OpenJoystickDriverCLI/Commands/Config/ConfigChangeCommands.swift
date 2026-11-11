import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// `ojd config set`: sets one tuning key in the user's record of a controller model, or in
/// `all.patch.plist` without `--controller`.
struct ConfigSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.config.set.abstract"),
    discussion: CLILocalized.text("cli.config.set.discussion")
  )

  /// The tuning key.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.config.group.key"), valueName: "KEY"))
  var key: String

  /// The value: every remaining argument is collected, so a negative number such as `-0.5` is a
  /// value and not an option; ``validate()`` requires exactly one.
  @Argument(
    parsing: .allUnrecognized,
    help: ArgumentHelp(CLILocalized.text("cli.config.set.value"), valueName: "VALUE")
  )
  var values: [String] = []

  /// `--controller`: the model whose record to change.
  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.group.controller"), valueName: "VVVV:PPPP")
  )
  var controller: ControllerModelID?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that the key and the value name a tuning edit.
  func validate() throws { _ = try edit() }

  /// Runs the command.
  func run() async throws {
    try await ConfigChange.run(try edit(), controller: controller, global: global)
  }

  /// The tuning edit that the key and the value name.
  private func edit() throws -> ControllerRecordWriter.TuningEdit {
    guard let value = values.first, values.count == 1 else {
      throw ValidationError(CLILocalized.text("cli.config.set.valueCount"))
    }
    return try ConfigChange.edit(key: key, value: value)
  }
}

/// `ojd config unset`: removes one tuning key from the user's record of a controller model, or
/// from `all.patch.plist` without `--controller`.
struct ConfigUnsetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "unset",
    abstract: CLILocalized.text("cli.config.unset.abstract")
  )

  /// The tuning key.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.config.group.key"), valueName: "KEY"))
  var key: String

  /// `--controller`: the model whose record to change.
  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.group.controller"), valueName: "VVVV:PPPP")
  )
  var controller: ControllerModelID?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that the key names a tuning edit that the command can remove.
  func validate() throws { _ = try ConfigChange.edit(key: key, value: nil) }

  /// Runs the command.
  func run() async throws {
    try await ConfigChange.run(
      try ConfigChange.edit(key: key, value: nil),
      controller: controller,
      global: global
    )
  }
}
