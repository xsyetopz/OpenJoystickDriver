import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd log export` command: writes the last lines of each service log to a file, with the home
/// folder shown as `~`.
struct LogExportCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: CLILocalized.text(
      "cli.log.export.abstract"
    )
  )

  /// The file to write.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.file"),
      valueName: "file"
    )
  )
  var file: String

  /// `--lines`: how many of the last lines of each log to export.
  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines"),
      valueName: "count"
    )
  )
  var lines = ApplicationServiceLogService.defaultExportLines

  /// `-f`, `--force`: replace an existing file.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.force")
    )
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result.
  private struct Result: Encodable {
    /// The path of the file.
    let path: String
    /// The number of lines written.
    let lines: Int
  }

  /// Checks that `lines` is within the range that the service allows.
  ///
  /// - Throws: ``ValidationError`` when it is not.
  func validate() throws {
    guard ApplicationServiceLogService.linesRange.contains(lines) else {
      throw ValidationError(
        CLILocalized.text("cli.log.show.linesRange")
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let environment = LogCommand.environment
      let snapshots: [ApplicationServiceLogSnapshot]
      do {
        snapshots = try ApplicationServiceLogStream.allCases.map { try environment.tail($0, lines) }
      } catch {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.log.show.readFailed",
            error.localizedDescription
          )
        )
      }
      let url = URL(fileURLWithPath: file)
      guard force || !FileManager.default.fileExists(atPath: url.path) else {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.log.export.exists",
            url.path
          )
        )
      }
      let text = ApplicationServiceLogService.exportText(
        snapshots,
        home: MacOSDataDirectory().url(for: .home).path
      )
      do {
        try Data(text.utf8).write(to: url, options: force ? .atomic : .withoutOverwriting)
      } catch {
        throw CLIFailure(
          .fileAccessFailed,
          CLILocalized.format(
            "cli.record.install.failed",
            url.path,
            error.localizedDescription
          )
        )
      }
      CLIOutput.stderr(ApplicationServiceLogService.sharingWarning)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          CLIStatus(
            details: Result(path: url.path, lines: snapshots.map(\.lines.count).reduce(0, +))
          )
        )
      case .plain: CLIOutput.plain([[url.path]])
      case .human:
        CLIOutput.success(
          CLILocalized.format("cli.log.export.written", url.path)
        )
      }
    }
  }
}
