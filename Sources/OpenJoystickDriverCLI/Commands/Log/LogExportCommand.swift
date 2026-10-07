import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct LogExportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: CLILocalized.text(
      "cli.log.export.abstract"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.file"),
      valueName: "file"
    )
  )
  var file: String

  @Option(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.show.lines"),
      valueName: "count"
    )
  )
  var lines = 2000

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.log.export.force")
    )
  )
  var force = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  private struct Result: Encodable {
    let path: String
    let lines: Int
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
      let text = ApplicationServiceLogService.redactingHome(
        LogShowCommand.humanText(snapshots),
        home: FileManager.default.homeDirectoryForCurrentUser.path
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
