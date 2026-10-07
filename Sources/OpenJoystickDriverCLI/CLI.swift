import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd` entry point.
package struct CLI {
  package init() {}

  @MainActor
  package func run(arguments: [String]) async -> Never {
    installCLIShutdownHandlers()
    // Profile validation reads the same bundled and user records as the app.
    ControllerRecordSet.load().activate()
    let code = await Self.execute(arguments: arguments)
    fflush(stdout)
    exit(code)
  }

  /// Parses and runs one `ojd` invocation, prints its failure, and returns its exit code.
  static func execute(arguments: [String]) async -> Int32 {
    let completing = arguments.contains("--generate-completion-script")
    return await GlobalOptions.$subcommandVisibility.withValue(completing ? .default : .hidden) {
      await parseAndRun(arguments: arguments)
    }
  }

  private static func parseAndRun(arguments: [String]) async -> Int32 {
    var command: any ParsableCommand
    do { command = try OJDCommand.parseAsRoot(arguments) } catch {
      if let match = CommandSuggestion.match(arguments: arguments) {
        guard let suggestion = match.suggestion else {
          return reportLibraryError(error, code: .unknownCommand)
        }
        CLIOutput.stderr(
          CLIFailure.prefix(.unknownCommand)
            + CLILocalized.format(
              "cli.error.unknown_command",
              match.typed,
              suggestion
            )
        )
        return CLIExitCode.usage.rawValue
      }
      return reportLibraryError(error)
    }
    // Every ojd command is async; a synchronous one is the library's help command, whose
    // "error" is the help text.
    guard var asyncCommand = command as? any AsyncParsableCommand else {
      do { try command.run() } catch { return reportLibraryError(error) }
      return CLIExitCode.success.rawValue
    }
    do {
      try await CLIOutput.$kind.withValue(outputKind(of: type(of: asyncCommand)) ?? "") {
        try await asyncCommand.run()
      }
      return CLIExitCode.success.rawValue
    } catch { return report(error) }
  }

  static func exitCode(for error: any Error) -> Int32 {
    switch error {
    case let failure as CLIFailure: failure.code.rawValue
    case is CancellationError: CLIExitCode.interrupted.rawValue
    case is CleanExit, is ExitCode, is ValidationError: OJDCommand.exitCode(for: error).rawValue
    default: CLIExitCode.failure.rawValue
    }
  }

  private static func report(_ error: any Error) -> Int32 {
    switch error {
    case let failure as CLIFailure: CLIOutput.stderr(failure.line)
    case is CancellationError: break
    case is CleanExit, is ExitCode, is ValidationError: return reportLibraryError(error)
    default:
      CLIOutput.stderr(
        CLIFailure.prefix(.unexpected)
          + CLILocalized.format(
            "cli.error.unexpected",
            String(describing: error).replacingOccurrences(of: "\n", with: " ")
          )
      )
    }
    return exitCode(for: error)
  }

  /// Prints a parser result: help and the version on stdout, usage errors on stderr. A usage
  /// error carries the usage code unless `code` names another.
  private static func reportLibraryError(
    _ error: any Error,
    code errorCode: ErrorCode = .usage
  ) -> Int32 {
    let code = OJDCommand.exitCode(for: error).rawValue
    var message = OJDCommand.fullMessage(for: error)
    if errorCode != .usage, message.hasPrefix(OJDCommand._errorPrefix) {
      message = CLIFailure.prefix(errorCode) + message.dropFirst(OJDCommand._errorPrefix.count)
    }
    // Only the root help lists the global options; subcommand help points to it.
    let isHelp = message.hasPrefix("OVERVIEW: ") || message.hasPrefix("USAGE: ")
    if code == CLIExitCode.success.rawValue, isHelp, message != OJDCommand.helpMessage() {
      message += "\n" + CLILocalized.text("cli.help.global_options")
    }
    if !message.isEmpty {
      if code == CLIExitCode.success.rawValue {
        CLIOutput.stdout(message)
      } else {
        CLIOutput.stderr(message)
      }
    }
    return code
  }
}
