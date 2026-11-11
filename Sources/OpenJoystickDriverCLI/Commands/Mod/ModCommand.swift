import ArgumentParser

/// The `ojd mod` command group: validate, install, list and remove mod packages.
struct ModCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "mod",
    abstract: CLILocalized.text("cli.mod.group.abstract"),
    discussion: CLILocalized.text("cli.mod.group.discussion"),
    subcommands: [
      ModValidateCommand.self, ModInstallCommand.self, ModListCommand.self, ModRemoveCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}
