import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd generate` command: runs a generator script and writes the documents it returns.
struct GenerateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "generate",
    abstract: CLILocalized.text("cli.generate.group.abstract"),
    discussion: CLILocalized.text("cli.generate.group.discussion")
  )

  /// The seconds a script may run when `--timeout` is not set.
  static let defaultTimeout = 5.0

  /// The executable that runs as the helper process; tests replace it.
  @TaskLocal
  static var helper: URL? = Bundle.main.executableURL

  /// The generator script.
  @Argument(
    help: ArgumentHelp(CLILocalized.text("cli.generate.group.script"), valueName: "SCRIPT")
  )
  var script: String

  /// The global options, whose `--timeout` is the time limit of the script.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard let helper = Self.helper else {
        throw CLIFailure(
          .launchFailed,
          CLILocalized.format("cli.generate.group.helperFailed", "no executable")
        )
      }
      let limit = CLIContext.current.timeout ?? Self.defaultTimeout
      let outcome: GenerateRunner.Outcome
      do {
        outcome = try await GenerateRunner.run(
          executable: helper,
          script: URL(fileURLWithPath: script),
          timeout: limit
        )
      } catch {
        throw CLIFailure(
          .launchFailed,
          CLILocalized.format("cli.generate.group.helperFailed", error.localizedDescription)
        )
      }
      if outcome.timedOut {
        throw CLIFailure(
          .aborted,
          CLILocalized.format("cli.generate.group.timedOut", script, String(limit))
        )
      }
    }
  }
}
