import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// `ojd controller claim`: sets `server` to `OJD` for the controller's model, so OJD serves it.
struct ControllerClaimCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "claim",
    abstract: CLILocalized.text("cli.controller.claim.abstract"),
    discussion: CLILocalized.text("platform.macos.cli.controller.claim.discussion")
  )

  /// The controller to claim.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.dryRun"))
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await ControllerServerChange.run(
      .ojd,
      controller: controller,
      dryRun: dryRun,
      global: global
    )
  }
}

/// `ojd controller release`: sets `server` to `System` for the controller's model, so the system
/// serves it.
struct ControllerReleaseCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "release",
    abstract: CLILocalized.text("platform.macos.cli.controller.release.abstract"),
    discussion: CLILocalized.text("platform.macos.cli.controller.release.discussion")
  )

  /// The controller to release.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.dryRun"))
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await ControllerServerChange.run(
      .system,
      controller: controller,
      dryRun: dryRun,
      global: global
    )
  }
}
