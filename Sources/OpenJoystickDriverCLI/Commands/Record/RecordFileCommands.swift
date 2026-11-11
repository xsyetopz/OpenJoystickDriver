import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `record validate` and `record install`.
struct RecordValidation: Encodable, Equatable {
  /// Whether the record is valid.
  let valid: Bool
  /// Why the record is not valid.
  let problem: String?
  /// Whether the record is a `Controller` or a `ControllerPatch`.
  let operation: String?
  /// The controller model as `VVVV:PPPP`.
  let identity: String?
  /// The protocol family of the record.
  let family: String?
  /// The file name that an installed record gets.
  let fileName: String?
  /// How OJD reaches the controller.
  let transport: RecordTransport?
  /// Whether the DriverKit extension can claim a raw-USB controller.
  let transportClaim: RecordTransportClaim?

  /// Describes a valid record.
  init(_ validated: ValidatedControllerRecord) {
    valid = true
    problem = nil
    operation = validated.operation.rawValue
    identity = validated.record.map {
      deviceIdentity(vendorID: Int($0.model.vendorID), productID: Int($0.model.productID))
    }
    family = validated.record?.family
    fileName = validated.fileName
    transport = validated.record.map(RecordTransport.init)
    transportClaim = validated.record.flatMap(RecordTransportClaim.init)
  }

  /// Describes an invalid record by its `problem`.
  init(problem: String) {
    valid = false
    self.problem = problem
    operation = nil
    identity = nil
    family = nil
    fileName = nil
    transport = nil
    transportClaim = nil
  }

  /// Validates the bytes read from `path`, `-` for stdin.
  ///
  /// An invalid record prints `valid: false` with `--json` and exits 1.
  ///
  /// - Throws: ``CLIFailure`` when the record is not valid.
  static func check(_ path: String, data: Data) throws -> ValidatedControllerRecord {
    do { return try ControllerRecordSet.validate(data) } catch {
      let problem = ControllerRecordSet.problemDescription(
        error,
        includingCode: false,
        document: "record"
      )
      if CLIContext.current.format == .json { try CLIOutput.json(Self(problem: problem)) }
      throw CLIFailure(
        ControllerRecordSet.problemCode(error) ?? .invalidInputFile,
        CLILocalized.format("cli.record.group.invalid", path, problem)
      )
    }
  }
}

/// The `FILE|-` operand of `record validate` and `record install`.
private func recordFileHelp() -> ArgumentHelp {
  ArgumentHelp(
    CLILocalized.text("cli.record.group.file"),
    valueName: "FILE|-"
  )
}

/// The `ojd record validate` command: checks a record without installing it.
struct RecordValidateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text(
      "cli.record.validate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.validate.discussion"
    )
  )

  /// The record file to read, or `-` for standard input.
  @Argument(help: recordFileHelp())
  var file: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let validated = try RecordValidation.check(file, data: RecordStore.read(file))
      let result = RecordValidation(validated)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.operation.map(CommandLineName.kebab) ?? "", result.identity ?? "",
            result.family.map(CommandLineName.kebab) ?? "",
            result.fileName ?? "",
            result.transport.map { CommandLineName.kebab($0.rawValue) } ?? "",
            result.transportClaim.map { CommandLineName.kebab($0.rawValue) } ?? "",
          ]
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.record.validate.valid",
            file,
            CommandLineName.kebab(validated.operation.rawValue),
            result.identity ?? "",
            validated.record.map { CommandLineName.kebab($0.family) } ?? ""
          )
        )
        if let note = validated.record?.usbNote { CLIOutput.stdout(note) }
        if let note = validated.record?.bluetoothLENote {
          CLIOutput.stdout(note)
        }
      }
    }
  }
}

/// The `ojd record install` command: checks a record and writes it to the user's record folder as
/// `vvvv-pppp.plist`.
///
/// Replacing an installed record needs a confirmation, or `--force` without a terminal.
struct RecordInstallCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: CLILocalized.text(
      "cli.record.install.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.install.discussion"
    ) + "\n\n" + CLILocalized.text("cli.record.install.examples")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The path of the installed record.
    let installed: String
    /// Whether the command replaces an installed record.
    let replaced: Bool
    /// Whether `--dry-run` is set, so nothing is written.
    let dryRun: Bool
    /// The validation of the record.
    let record: RecordValidation
  }

  /// The record file to read, or `-` for standard input.
  @Argument(help: recordFileHelp())
  var file: String

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: check the record and print where it would go, and write nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.dryRun")
    )
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let data = try RecordStore.read(file)
      let validated = try RecordValidation.check(file, data: data)
      let destination = RecordStore.directory.appendingPathComponent(validated.fileName)
      let replaced = FileManager.default.fileExists(atPath: destination.path)
      if replaced, !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format("cli.record.install.confirm", destination.path),
          force: force
        )
      }
      if !dryRun { try write(data, to: destination) }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            installed: destination.path,
            replaced: replaced,
            dryRun: dryRun,
            record: RecordValidation(validated)
          )
        )
      case .plain: CLIOutput.plain([[destination.path]])
      case .human:
        if dryRun {
          CLIOutput.stdout(
            CLILocalized.format("cli.record.install.dryRun", destination.path)
          )
        } else {
          CLIOutput.success(
            CLILocalized.format(
              "cli.record.install.success",
              destination.path
            )
          )
        }
      }
      if let note = validated.record?.usbNote { CLIOutput.stderr(note) }
    }
  }

  /// Writes `data` to `destination`.
  ///
  /// - Throws: ``CLIFailure`` when the file cannot be written.
  private func write(_ data: Data, to destination: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: RecordStore.directory,
        withIntermediateDirectories: true
      )
      try data.write(to: destination, options: .atomic)
    } catch {
      throw CLIFailure(
        .fileAccessFailed,
        CLILocalized.format(
          "cli.record.install.failed",
          destination.path,
          error.localizedDescription
        )
      )
    }
  }
}

/// The `ojd record remove` command: deletes the user's record for a model.
struct RecordRemoveCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: CLILocalized.text(
      "cli.record.remove.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.remove.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The paths of the removed record files.
    let removed: String
    /// Whether `--dry-run` is set, so nothing is removed.
    let dryRun: Bool
  }

  /// The model whose record to remove.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.group.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var model: ControllerModelID

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.dryRun")
    )
  )
  var dryRun = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let targets = [
        ControllerRecordSet.fileName(for: model),
        ControllerPatch.Selector.identity(model).fileName,
      ].map { RecordStore.directory.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !targets.isEmpty else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.record.remove.notFound",
            model.description
          )
        )
      }
      let paths = targets.map(\.path).joined(separator: ", ")
      if !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format("cli.record.remove.confirm", paths),
          force: force
        )
        for target in targets {
          do { try FileManager.default.removeItem(at: target) } catch {
            throw CLIFailure(
              .fileAccessFailed,
              CLILocalized.format(
                "cli.record.remove.failed",
                target.path,
                error.localizedDescription
              )
            )
          }
        }
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIStatus(details: Result(removed: paths, dryRun: dryRun)))
      case .plain: CLIOutput.plain(targets.map { [$0.path] })
      case .human:
        if dryRun {
          CLIOutput.stdout(
            CLILocalized.format("cli.record.remove.dryRun", paths)
          )
        } else {
          CLIOutput.success(
            CLILocalized.format("cli.record.remove.success", paths)
          )
        }
      }
    }
  }
}
