import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd migrate` command: converts the stored documents of an older `apiVersion`.
struct MigrateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "migrate",
    abstract: CLILocalized.text("cli.migrate.abstract"),
    discussion: CLILocalized.text("cli.migrate.discussion")
  )

  /// The data directory whose support folder is migrated; tests replace it so they never touch the
  /// user's real files.
  @TaskLocal
  static var directory: any DataDirectory = MacOSDataDirectory()

  /// `--dry-run`: list the documents and change nothing.
  @Flag(
    name: .long,
    help: ArgumentHelp(CLILocalized.text("cli.migrate.dryRun"))
  )
  var dryRun = false

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
      let entries = DocumentMigrator(directory: Self.directory).run(dryRun: dryRun)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIList(metadata: Metadata(dryRun: dryRun), items: entries))
      case .plain:
        CLIOutput.plain(entries.map { [$0.status.rawValue, $0.file, $0.detail ?? ""] })
      case .human:
        if entries.isEmpty { CLIOutput.stdout(CLILocalized.text("cli.migrate.none")) }
        for entry in entries { CLIOutput.stdout(Self.line(entry)) }
      }
      guard entries.allSatisfy({ $0.status != .failed }) else {
        throw CLIFailure(.documentNotMigrated, CLILocalized.text("cli.migrate.failedSummary"))
      }
    }
  }

  /// The line of `entry` in the human output.
  private static func line(_ entry: DocumentMigrator.Entry) -> String {
    switch entry.status {
    case .converted: CLILocalized.format("cli.migrate.converted", entry.file)
    case .wouldConvert: CLILocalized.format("cli.migrate.wouldConvert", entry.file)
    case .failed:
      CLILocalized.format("cli.migrate.failed", entry.file, entry.detail ?? "")
    }
  }
}
