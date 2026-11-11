import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd migrate` command: converts the stored documents of an older `apiVersion` and gives
/// each file it scans a verdict.
struct MigrateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "migrate",
    abstract: CLILocalized.text("cli.migrate.group.abstract"),
    discussion: CLILocalized.text("cli.migrate.group.discussion")
  )

  /// The data directory whose support folder is migrated; tests replace it so they never touch the
  /// user's real files.
  @TaskLocal
  static var directory: any DataDirectory = MacOSDataDirectory()

  /// `--dry-run`: list the documents and change nothing.
  @Flag(
    name: .long,
    help: ArgumentHelp(CLILocalized.text("cli.migrate.group.dryRun"))
  )
  var dryRun = false

  /// The folder to scan instead of the support folder.
  @Argument(
    help: ArgumentHelp(CLILocalized.text("cli.migrate.group.folder")),
    completion: .directory
  )
  var folder: String?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` metadata.
  private struct Metadata: Encodable {
    /// Whether the run only listed the documents.
    let dryRun: Bool
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let url = folder.map {
        URL(fileURLWithPath: $0.hasPrefix("~") ? NSHomeDirectory() + $0.dropFirst() : $0)
      }
      let entries = DocumentMigrator(directory: Self.directory).run(dryRun: dryRun, folder: url)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIList(metadata: Metadata(dryRun: dryRun), items: entries))
      case .plain:
        CLIOutput.plain(entries.map { [$0.verdict.rawValue, $0.file, $0.detail ?? ""] })
      case .human:
        if entries.isEmpty { CLIOutput.stdout(CLILocalized.text("cli.migrate.group.none")) }
        for entry in entries { CLIOutput.stdout(line(entry)) }
      }
      guard entries.allSatisfy({ $0.verdict != .failed }) else {
        throw CLIFailure(.documentNotMigrated, CLILocalized.text("cli.migrate.group.failedSummary"))
      }
    }
  }

  /// The line of `entry` in the human output.
  private func line(_ entry: DocumentMigrator.Entry) -> String {
    switch entry.verdict {
    case .migrated:
      CLILocalized.format(
        dryRun ? "cli.migrate.group.wouldConvert" : "cli.migrate.group.converted",
        entry.file
      )
    case .current: CLILocalized.format("cli.migrate.group.current", entry.file)
    case .foreign: CLILocalized.format("cli.migrate.group.foreign", entry.file)
    case .failed:
      CLILocalized.format("cli.migrate.group.failed", entry.file, entry.detail ?? "")
    }
  }
}
