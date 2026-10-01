import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd` entry point.
package struct CLI {
  package init() {}

  @MainActor
  package func run(arguments: [String]) async -> Never {
    installCLIShutdownHandlers()
    let code = await Self.execute(arguments: arguments)
    fflush(stdout)
    exit(code)
  }

  /// Parses and runs one `ojd` invocation, prints its failure, and returns its exit code.
  static func execute(arguments: [String]) async -> Int32 {
    var command: any ParsableCommand
    do { command = try OJDCommand.parseAsRoot(arguments) } catch {
      if let match = CommandSuggestion.match(arguments: arguments) {
        CLIOutput.stderr(
          "ojd: "
            + CLILocalized.format(
              "cli.error.unknown_command",
              "Unknown command '%@'. Did you mean '%@'?",
              match.typed,
              match.suggestion
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
      try await asyncCommand.run()
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
    case let failure as CLIFailure: CLIOutput.stderr("ojd: \(failure.message)")
    case is CancellationError: break
    case is CleanExit, is ExitCode, is ValidationError: return reportLibraryError(error)
    default:
      CLIOutput.stderr(
        "ojd: "
          + CLILocalized.format(
            "cli.error.unexpected",
            "Unexpected error: %@. Run 'ojd diagnose --bundle PATH' and attach the bundle "
              + "to a bug report.",
            String(describing: error).replacingOccurrences(of: "\n", with: " ")
          )
      )
    }
    return exitCode(for: error)
  }

  /// Prints a parser result: help and the version on stdout, usage errors on stderr.
  private static func reportLibraryError(_ error: any Error) -> Int32 {
    let code = OJDCommand.exitCode(for: error).rawValue
    let message = OJDCommand.fullMessage(for: error)
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
