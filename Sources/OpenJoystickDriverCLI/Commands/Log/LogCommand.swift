import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct LogCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: CLILocalized.text(
      "cli.log.abstract",
      "Show the service logs or print where they are."
    ),
    subcommands: [LogShowCommand.self, LogPathCommand.self, LogExportCommand.self]
  )

  /// Tests replace it so they never read real logs or spawn a pager.
  @TaskLocal
  static var environment = LogEnvironment.system

  @OptionGroup
  var global: GlobalOptions
}

struct LogPathCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "path",
    abstract: CLILocalized.text(
      "cli.log.path.abstract",
      "Print the folder that holds the service logs. Open it with: open \"$(ojd log path)\""
    )
  )

  @OptionGroup
  var global: GlobalOptions

  private struct Result: Encodable { let path: String }

  func run() async throws {
    try await global.run {
      let path = LogCommand.environment.directory().path
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(path: path))
      case .plain, .human: CLIOutput.stdout(path)
      }
    }
  }
}

struct LogShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.log.show.abstract", "Print the end of the service logs."),
    discussion: CLILocalized.text(
      "cli.log.show.discussion",
      "On a terminal the output goes through $PAGER (default 'less -FRX'; set PAGER to an empty "
        + "value to turn paging off). --follow keeps printing new lines until you press "
        + "Control-C; with --json it prints one JSON object per line."
    )
  )

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.follow", "Keep printing lines as the service writes them.")
    )
  )
  var follow = false

  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines", "Lines to print from each log, 1 to 10000."),
      valueName: "count"
    )
  )
  var lines = ApplicationServiceLogService.defaultMaximumLines

  @OptionGroup
  var global: GlobalOptions

  private struct Snapshots: Encodable { let logs: [ApplicationServiceLogSnapshot] }
  private struct StreamedLine: Encodable {
    let stream: ApplicationServiceLogStream
    let line: String
  }

  func validate() throws {
    guard (1...10_000).contains(lines) else {
      throw ValidationError(
        CLILocalized.text("cli.log.show.lines_range", "--lines must be between 1 and 10000.")
      )
    }
  }

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
            "cli.log.show.read_failed",
            "Could not read the service logs: %@. Check the folder that 'ojd log path' prints.",
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
        try environment.page(pager, Self.humanText(snapshots))
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

  private static func printSnapshots(
    _ snapshots: [ApplicationServiceLogSnapshot],
    format: CLIContext.Format,
    jsonLines: Bool
  ) throws {
    switch format {
    case .json where jsonLines:
      for snapshot in snapshots {
        for line in snapshot.lines {
          try printLine(StreamedLine(stream: snapshot.stream, line: line))
        }
      }
    case .json: try CLIOutput.json(Snapshots(logs: snapshots))
    case .plain:
      CLIOutput.plain(
        snapshots.flatMap { snapshot in snapshot.lines.map { [snapshot.stream.rawValue, $0] } }
      )
    case .human: CLIOutput.stdout(humanText(snapshots), terminator: "")
    }
  }

  static func humanText(_ snapshots: [ApplicationServiceLogSnapshot]) -> String {
    var text = ""
    for snapshot in snapshots {
      text += "== \(snapshot.stream.rawValue): \(snapshot.path) ==\n"
      if !snapshot.exists {
        text += CLILocalized.text("cli.log.show.missing", "(log file does not exist)") + "\n"
      } else if snapshot.lines.isEmpty {
        text += CLILocalized.text("cli.log.show.empty", "(log file is empty)") + "\n"
      }
      if snapshot.truncated {
        text += CLILocalized.text("cli.log.show.truncated", "(earlier log content omitted)") + "\n"
      }
      for line in snapshot.lines { text += line + "\n" }
    }
    return text
  }

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
            case .json: try? printLine(StreamedLine(stream: line.stream, line: line.text))
            case .plain: CLIOutput.plain([[line.stream.rawValue, line.text]])
            case .human: CLIOutput.stdout(line.text)
            }
          }
        }
      }
    }
    try Task.checkCancellation()
  }

  private static func printLine(_ line: StreamedLine) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    CLIOutput.stdout(String(bytes: try encoder.encode(line), encoding: .utf8) ?? "")
  }
}
