import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd log` command group: show, export and locate the service logs.
struct LogCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: CLILocalized.text(
      "cli.log.group.abstract"
    ),
    subcommands: [LogShowCommand.self, LogPathCommand.self, LogExportCommand.self]
  )

  /// The environment that `ojd log` reads logs through; tests replace it so they never read real
  /// logs or spawn a pager.
  @TaskLocal
  static var environment = LogEnvironment.system

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd log path` command: prints the folder that holds the service logs.
struct LogPathCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "path",
    abstract: CLILocalized.text(
      "cli.log.path.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result.
  private struct Result: Encodable {
    /// The path of the log folder.
    let path: String
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let path = LogCommand.environment.directory().path
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(path: path))
      case .plain, .human: CLIOutput.raw(path)
      }
    }
  }
}

/// The `ojd log show` command: prints the last lines of each service log, or follows them.
///
/// On a terminal the output goes through `$PAGER`.
struct LogShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.log.show.abstract"),
    discussion: CLILocalized.text(
      "cli.log.show.discussion"
    )
  )

  /// The `kind` of each `--json` line with `--follow`.
  private static let streamedLineKind = "LogEntry"

  /// `--follow`: keep printing appended lines until interrupted.
  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.follow")
    )
  )
  var follow = false

  /// `--lines`: how many of the last lines of each log to print.
  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines"),
      valueName: "count"
    )
  )
  var lines = ApplicationServiceLogService.defaultMaximumLines

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result: the snapshot of each log.
  private struct Snapshots: Encodable {
    /// The snapshot of each log.
    let logs: [ApplicationServiceLogSnapshot]
  }
  /// One `--json` line of `--follow`.
  private struct StreamedLine: Encodable {
    /// The log that the line came from.
    let stream: ApplicationServiceLogStream
    /// The text of the line.
    let line: String
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
      CLIOutput.stderr(ApplicationServiceLogService.sharingWarning)
      let format = CLIContext.current.format
      if follow {
        try Self.printSnapshots(snapshots, format: format, jsonLines: true)
        try await Self.stream(snapshots, environment: environment, format: format)
        return
      }
      if format == .human, environment.isTerminal(), let pager = Self.pagerCommand() {
        try environment.page(pager, ApplicationServiceLogService.humanText(snapshots))
        return
      }
      try Self.printSnapshots(snapshots, format: format, jsonLines: false)
    }
  }

  /// `$PAGER`, `less -FRX` when unset, or nil when set to an empty value.
  static func pagerCommand(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    guard let pager = environment["PAGER"] else { return "less -FRX" }
    let trimmed = pager.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Prints the snapshots as JSON, `--plain` rows or text, through the pager on a terminal.
  private static func printSnapshots(
    _ snapshots: [ApplicationServiceLogSnapshot],
    format: CLIContext.Format,
    jsonLines: Bool
  ) throws {
    switch format {
    case .json where jsonLines:
      for snapshot in snapshots {
        for line in snapshot.lines {
          try CLIOutput.jsonLine(
            StreamedLine(stream: snapshot.stream, line: line),
            kind: Self.streamedLineKind
          )
        }
      }
    case .json: try CLIOutput.json(Snapshots(logs: snapshots))
    case .plain:
      CLIOutput.plain(
        snapshots.flatMap { snapshot in
          snapshot.lines.map { [CommandLineName.kebab(snapshot.stream.rawValue), $0] }
        }
      )
    case .human: CLIOutput.stdout(ApplicationServiceLogService.humanText(snapshots), terminator: "")
    }
  }

  /// Prints the lines appended to the logs after `snapshots` until the task is cancelled.
  private static func stream(
    _ snapshots: [ApplicationServiceLogSnapshot],
    environment: LogEnvironment,
    format: CLIContext.Format
  ) async throws {
    await withTaskGroup(of: Void.self) { group in
      for snapshot in snapshots {
        group.addTask {
          for await line in environment.follow(snapshot.stream, snapshot.fileSizeBytes) {
            switch format {
            case .json:
              try? CLIOutput.jsonLine(
                StreamedLine(stream: line.stream, line: line.text),
                kind: Self.streamedLineKind
              )
            case .plain:
              CLIOutput.plain([[CommandLineName.kebab(line.stream.rawValue), line.text]])
            case .human: CLIOutput.stdout(line.text)
            }
          }
        }
      }
    }
    try Task.checkCancellation()
  }
}
