import ArgumentParser
import OpenJoystickDriverKit

/// The `ojd` root command.
struct OJDCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ojd",
    abstract: CLILocalized.text(
      "cli.root.abstract",
      "Configure and inspect OpenJoystickDriver, the macOS gamepad driver."
    ),
    discussion: CLILocalized.text(
      "cli.root.discussion",
      """
      Exit codes:
        0    Success.
        1    The command failed.
        64   Usage error.
        69   The service is not running. Start it with 'ojd service start'.
        77   A macOS permission is missing.
        130  Interrupted.
      """
    ),
    version: ApplicationVersion.current,
    subcommands: [
      StatusCommand.self, ControllerCommand.self, ProfileCommand.self, BindingCommand.self,
      VirtualCommand.self, ServiceCommand.self,
      RecordCommand.self, PermissionCommand.self, ExtensionCommand.self, SettingCommand.self,
      AccessCommand.self,
      LogCommand.self, DiagnoseCommand.self, UpdateCommand.self,
    ]
  )

  static var _errorPrefix: String { "ojd: " }

  @OptionGroup
  var global: GlobalOptions
}
