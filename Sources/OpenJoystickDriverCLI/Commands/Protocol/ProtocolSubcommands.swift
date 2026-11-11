import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `FILE` operand of `protocol validate` and `protocol install`.
private func protocolFileHelp() -> ArgumentHelp {
  ArgumentHelp(CLILocalized.text("cli.protocol.group.file"), valueName: "FILE")
}

/// The `ojd protocol validate` command: checks a protocol description file without installing it.
struct ProtocolValidateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text("cli.protocol.validate.abstract"),
    discussion: CLILocalized.text("cli.protocol.validate.discussion")
  )

  /// The description file.
  @Argument(help: protocolFileHelp())
  var file: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let family = try ProtocolStore.read(file)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(ProtocolValidation(family))
      case .plain: CLIOutput.plain([[family.name, family.displayName]])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format("cli.protocol.validate.valid", file, family.name, family.displayName)
        )
      }
    }
  }
}

/// The `ojd protocol install` command: checks a description and copies it to
/// `Protocols/FamilyName.plist`.
///
/// A description of the same name that is installed is replaced.
struct ProtocolInstallCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: CLILocalized.text("cli.protocol.install.abstract"),
    discussion: CLILocalized.text("cli.protocol.install.discussion")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The path of the installed file.
    let installed: String
    /// Whether the command replaces an installed file of the same name.
    let replaced: Bool
    /// Whether `--dry-run` is set, so nothing is installed.
    let dryRun: Bool
    /// The family name.
    let name: String
    /// The display name that the document gives.
    let displayName: String
  }

  /// The description file.
  @Argument(help: protocolFileHelp())
  var file: String

  /// `-n`, `--dry-run`: check the description and print where it would go, and write nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.dryRun"))
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let family = try ProtocolStore.read(file)
      let destination = ProtocolStore.directory.appendingPathComponent("\(family.name).plist")
      let replaced = FileManager.default.fileExists(atPath: destination.path)
      if !dryRun {
        try FileManager.default.createDirectory(
          at: ProtocolStore.directory,
          withIntermediateDirectories: true
        )
        try Data(contentsOf: family.file).write(to: destination, options: .atomic)
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            installed: destination.path,
            replaced: replaced,
            dryRun: dryRun,
            name: family.name,
            displayName: family.displayName
          )
        )
      case .plain: CLIOutput.plain([[destination.path]])
      case .human:
        if dryRun {
          CLIOutput.stdout(CLILocalized.format("cli.mod.install.dryRun", destination.path))
        } else {
          CLIOutput.success(CLILocalized.format("cli.protocol.install.success", destination.path))
        }
      }
    }
  }
}

/// The `ojd protocol list` command: prints each protocol family with where it comes from.
struct ProtocolListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.protocol.list.abstract"),
    discussion: CLILocalized.text("cli.protocol.list.discussion")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let entries =
        PhysicalProtocolID.allCases.map(ProtocolEntry.init(builtIn:))
        + DocumentedProtocolFamilies.load(besides: ProtocolStore.controllers).families.map(
          ProtocolEntry.init
        )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIList(items: entries))
      case .plain:
        CLIOutput.plain(
          entries.map { [$0.name, $0.displayName, $0.source.rawValue, $0.package ?? "", $0.file ?? ""] }
        )
      case .human:
        for entry in entries {
          CLIOutput.stdout("\(entry.name)  \(entry.displayName)  \(entry.sourceText)")
        }
      }
    }
  }
}
