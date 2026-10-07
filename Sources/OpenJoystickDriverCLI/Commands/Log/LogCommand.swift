import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct LogCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: CLILocalized.text(
      "cli.log.abstract"
    ),
    subcommands: [LogShowCommand.self, LogPathCommand.self, LogExportCommand.self]
  )

  /// Tests replace it so they never read real logs or spawn a pager.
  @TaskLocal
  static var environment = LogEnvironment.system

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct LogPathCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "path",
    abstract: CLILocalized.text(
      "cli.log.path.abstract"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
    abstract: CLILocalized.text("cli.log.show.abstract"),
    discussion: CLILocalized.text(
      "cli.log.show.discussion"
    )
  )

  /// The `kind` of each `--json` line with `--follow`.
  private static let streamedLineKind = "LogEntry"

  @Flag(
    name: .shortAndLong,
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.follow")
    )
  )
  var follow = false

  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines"),
      valueName: "count"
    )
  )
  var lines = ApplicationServiceLogService.defaultMaximumLines

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  private struct Snapshots: Encodable { let logs: [ApplicationServiceLogSnapshot] }
  private struct StreamedLine: Encodable {
    let stream: ApplicationServiceLogStream
    let line: String
  }

  func validate() throws {
    guard ApplicationServiceLogService.linesRange.contains(lines) else {
      throw ValidationError(
        CLILocalized.text("cli.log.show.lines_range")
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
          try CLIOutput.jsonLine(
            StreamedLine(stream: snapshot.stream, line: line),
            kind: Self.streamedLineKind
          )
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
        text += CLILocalized.text("cli.log.show.missing") + "\n"
      } else if snapshot.lines.isEmpty {
        text += CLILocalized.text("cli.log.show.empty") + "\n"
      }
      if snapshot.truncated {
        text += CLILocalized.text("cli.log.show.truncated") + "\n"
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
            case .json:
              try? CLIOutput.jsonLine(
                StreamedLine(stream: line.stream, line: line.text),
                kind: Self.streamedLineKind
              )
            case .plain: CLIOutput.plain([[line.stream.rawValue, line.text]])
            case .human: CLIOutput.stdout(line.text)
            }
          }
        }
      }
    }
    try Task.checkCancellation()
  }
}
