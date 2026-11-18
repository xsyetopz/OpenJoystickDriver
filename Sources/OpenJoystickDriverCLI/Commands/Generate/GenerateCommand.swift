import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd generate` command: runs a generator script and writes the documents it returns.
struct GenerateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "generate",
    abstract: CLILocalized.text("cli.generate.group.abstract"),
    discussion: CLILocalized.text("cli.generate.group.discussion")
  )

  /// The seconds a script may run when `--timeout` is not set.
  static let defaultTimeout = 5.0

  /// The executable that runs as the helper process; tests replace it.
  @TaskLocal
  static var helper: URL? = Bundle.main.executableURL

  /// The generator script.
  @Argument(
    help: ArgumentHelp(CLILocalized.text("cli.generate.group.script"), valueName: "SCRIPT")
  )
  var script: String

  /// `--output`: the folder that receives the files; without it the command writes no file.
  @Option(
    name: .long,
    help: ArgumentHelp(CLILocalized.text("cli.generate.group.output"), valueName: "FOLDER")
  )
  var output: String?

  /// `--replace`: overwrite a file whose content differs.
  @Flag(name: .long, help: ArgumentHelp(CLILocalized.text("cli.generate.group.replace")))
  var replace = false

  /// The global options, whose `--timeout` is the time limit of the script.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` metadata.
  private struct Metadata: Encodable {
    /// The folder that received the files, or nil when the command wrote none.
    let output: String?
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let documents = try await Self.documents(of: script)
      let entries =
        try output.map { try Self.write(documents, to: URL(fileURLWithPath: $0), replace: replace) }
        ?? documents.map { Entry(document: $0, status: .notWritten) }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIList(metadata: Metadata(output: output), items: entries))
      case .plain:
        CLIOutput.plain(entries.map { [$0.status.rawValue, $0.file, $0.kind] })
      case .human:
        for entry in entries { CLIOutput.stdout(entry.line) }
      }
    }
  }
}
