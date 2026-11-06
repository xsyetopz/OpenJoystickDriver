import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `FOLDER` operand of `mod validate` and `mod install`.
private func modFolderHelp() -> ArgumentHelp {
  ArgumentHelp(CLILocalized.text("cli.mod.group.folder"), valueName: "FOLDER")
}

/// The `ojd mod validate` command: checks a package folder without installing it.
struct ModValidateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text("cli.mod.validate.abstract"),
    discussion: CLILocalized.text("cli.mod.validate.discussion")
  )

  /// The package folder that holds `mod.json`.
  @Argument(help: modFolderHelp())
  var folder: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let manifest = try ModPackageValidation.check(folder)
      let result = ModPackageValidation(manifest)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([[manifest.name, manifest.version, manifest.author]])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.mod.validate.valid",
            folder,
            manifest.name,
            manifest.version
          )
        )
      }
    }
  }
}

/// The `ojd mod install` command: checks a package and installs it to `Packages/NAME`.
///
/// A package of the same name that is installed is refused unless `--force` is set.
struct ModInstallCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: CLILocalized.text("cli.mod.install.abstract"),
    discussion: CLILocalized.text("cli.mod.install.discussion")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The path of the installed package.
    let installed: String
    /// Whether the command replaces an installed package of the same name.
    let replaced: Bool
    /// Whether `--dry-run` is set, so nothing is installed.
    let dryRun: Bool
    /// The validation of the package.
    let package: ModPackageValidation
  }

  /// The package folder that holds `mod.json`.
  @Argument(help: modFolderHelp())
  var folder: String

  /// `-f`, `--force`: replace an installed package of the same name.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.mod.install.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: check the package and print where it would go, and write nothing.
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
      // Validation never depends on `--force`, so `requires` and clashes always refuse.
      let manifest = try ModPackageValidation.check(folder)
      let destination = ModStore.directory.appendingPathComponent(
        manifest.name,
        isDirectory: true
      )
      let replaced = (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil
      if replaced && !force {
        throw CLIFailure(
          .packageAlreadyInstalled,
          CLILocalized.format("cli.mod.group.alreadyInstalled", manifest.name)
        )
      }
      if !dryRun {
        do { try ModStore.store.install(ModStore.folder(folder), replace: force) } catch let error
          as ModPackageError
        {
          throw ModStore.failure(error, subject: folder)
        }
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            installed: destination.path,
            replaced: replaced,
            dryRun: dryRun,
            package: ModPackageValidation(manifest)
          )
        )
      case .plain: CLIOutput.plain([[destination.path]])
      case .human:
        if dryRun {
          CLIOutput.stdout(CLILocalized.format("cli.mod.install.dryRun", destination.path))
        } else {
          CLIOutput.success(CLILocalized.format("cli.mod.install.success", destination.path))
        }
      }
    }
  }
}

/// The `ojd mod list` command: prints each installed package with its version, author and files.
struct ModListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.mod.list.abstract"),
    discussion: CLILocalized.text("cli.mod.list.discussion")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let entries = ModStore.store.list().map(ModPackageEntry.init)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIList(items: entries))
      case .plain:
        CLIOutput.plain(
          entries.map {
            [
              $0.name, $0.version ?? "", $0.author ?? "", $0.files.joined(separator: ","),
              $0.problem ?? "",
            ]
          }
        )
      case .human:
        for entry in entries {
          CLIOutput.stdout(
            [entry.name, entry.version, entry.author].compactMap { $0 }.joined(separator: "  ")
          )
          for file in entry.files { CLIOutput.stdout("  \(file)") }
          if let problem = entry.problem {
            CLIOutput.stdout(CLILocalized.format("cli.mod.list.problem", problem))
          }
        }
      }
    }
  }
}

/// The `ojd mod remove` command: deletes one installed package.
struct ModRemoveCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: CLILocalized.text("cli.mod.remove.abstract"),
    discussion: CLILocalized.text("cli.mod.remove.discussion")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The path of the package folder.
    let removed: String
    /// Whether `--dry-run` is set, so nothing is removed.
    let dryRun: Bool
  }

  /// The name of the installed package.
  @Argument(help: ArgumentHelp(CLILocalized.text("cli.mod.group.name"), valueName: "NAME"))
  var name: String

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: print what would change and change nothing.
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
      let target = ModStore.directory.appendingPathComponent(name, isDirectory: true)
      // The name rules of `ModPackageStore.remove`: a name with a separator or a leading dot
      // names no entry. The check comes first, so a missing package is E4006 in every mode.
      let named = !name.isEmpty && !name.hasPrefix(".") && !name.contains("/")
      guard named, (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil else {
        throw CLIFailure(
          .packageNotInstalled,
          CLILocalized.format("cli.mod.group.notInstalled", name)
        )
      }
      if !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format("cli.mod.remove.confirm", target.path),
          force: force
        )
        do { try ModStore.store.remove(name) } catch let error as ModPackageError {
          throw ModStore.failure(error, subject: name)
        }
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIStatus(details: Result(removed: target.path, dryRun: dryRun)))
      case .plain: CLIOutput.plain([[target.path]])
      case .human:
        if dryRun {
          CLIOutput.stdout(CLILocalized.format("cli.mod.remove.dryRun", target.path))
        } else {
          CLIOutput.success(CLILocalized.format("cli.mod.remove.success", target.path))
        }
      }
    }
  }
}
