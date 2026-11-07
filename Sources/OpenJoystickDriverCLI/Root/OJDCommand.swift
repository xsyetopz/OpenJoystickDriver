import ArgumentParser
import OpenJoystickDriverKit

/// The `ojd` root command.
struct OJDCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "ojd",
    abstract: CLILocalized.text(
      "platform.macos.cli.root.group.abstract"
    ),
    discussion: CLILocalized.text(
      "platform.macos.cli.root.group.discussion"
    ),
    version: ApplicationVersion.buildIdentity.aboutLine,
    subcommands: [
      StatusCommand.self, ControllerCommand.self, ProfileCommand.self, BindingCommand.self,
      MacroCommand.self,
      VirtualCommand.self, ServiceCommand.self,
      RecordCommand.self, ModCommand.self, PermissionCommand.self, TransportExtensionCommand.self,
      SettingCommand.self,
      ConfigCommand.self, AccessCommand.self,
      LogCommand.self, DiagnoseCommand.self, UpdateCommand.self, ExplainCommand.self,
    ]
  )

  /// The parser reports only usage errors, so each carries the usage code.
  static var _errorPrefix: String { CLIFailure.prefix(.usage) }

  /// The global options.
  @OptionGroup
  var global: GlobalOptions
}
