import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct LogExportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: CLILocalized.text(
      "cli.log.export.abstract",
      "Write the end of the service logs to a file, with your home folder shown as ~."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.file", "The file to write."),
      valueName: "file"
    )
  )
  var file: String

  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines", "Lines to print from each log, 1 to 10000."),
      valueName: "count"
    )
  )
  var lines = 2000

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.force", "Replace the file if it exists.")
    )
  )
  var force = false

  @OptionGroup
  var global: GlobalOptions

  private struct Result: Encodable {
    let path: String
    let lines: Int
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
          .failure,
          CLILocalized.format(
            "cli.log.show.read_failed",
            "Could not read the service logs: %@. Check the folder that 'ojd log path' prints.",
            error.localizedDescription
          )
        )
      }
      let url = URL(fileURLWithPath: file)
      guard force || !FileManager.default.fileExists(atPath: url.path) else {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.log.export.exists",
            "%@ already exists. Pass --force to replace it.",
            url.path
          )
        )
      }
      let text = Self.redactingHome(
        LogShowCommand.humanText(snapshots),
        home: FileManager.default.homeDirectoryForCurrentUser.path
      )
      do {
        try Data(text.utf8).write(to: url, options: force ? .atomic : .withoutOverwriting)
      } catch {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.record.install.failed",
            "Cannot write %@: %@",
            url.path,
            error.localizedDescription
          )
        )
      }
      CLIOutput.stderr(ApplicationServiceLogService.sharingWarning)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(Result(path: url.path, lines: snapshots.map(\.lines.count).reduce(0, +)))
      case .plain: CLIOutput.plain([[url.path]])
      case .human:
        CLIOutput.success(
          CLILocalized.format("cli.log.export.written", "Wrote the service logs to %@.", url.path)
        )
      }
    }
  }

  /// `text` with each path under `home` written as `~`, as the support report leaves out
  /// filesystem paths. A longer folder name that starts with `home` is left alone.
  static func redactingHome(_ text: String, home: String) -> String {
    let home = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !home.isEmpty,
      let expression = try? NSRegularExpression(
        pattern: NSRegularExpression.escapedPattern(for: home) + #"(?=$|[/\s"':,;)\]])"#,
        options: .anchorsMatchLines
      )
    else { return text }
    return expression.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: "~"
    )
  }
}
