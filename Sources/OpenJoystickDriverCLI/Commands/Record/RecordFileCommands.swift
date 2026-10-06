import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `record validate` and `record install`.
struct RecordValidation: Encodable, Equatable {
  let valid: Bool
  let problem: String?
  let operation: String?
  let identity: String?
  let family: String?
  let fileName: String?
  let transport: RecordTransport?
  let usbExtension: RecordUSBExtension?

  init(_ validated: ValidatedControllerRecord) {
    valid = true
    problem = nil
    operation = validated.operation.rawValue
    identity = deviceIdentity(
      vendorID: Int(validated.record.identity.vendorID),
      productID: Int(validated.record.identity.productID)
    )
    family = validated.record.family
    fileName = validated.fileName
    transport = RecordTransport(validated.record)
    usbExtension = RecordUSBExtension(validated.record)
  }

  init(problem: String) {
    valid = false
    self.problem = problem
    operation = nil
    identity = nil
    family = nil
    fileName = nil
    transport = nil
    usbExtension = nil
  }

  /// Validates the bytes read from `path`, `-` for stdin. An invalid record prints
  /// `valid: false` with `--json` and exits 1.
  static func check(_ path: String, data: Data) throws -> ValidatedControllerRecord {
    do { return try ControllerRecordSet.validate(data) } catch {
      let problem = ControllerRecordSet.problemDescription(error)
      if CLIContext.current.format == .json { try CLIOutput.json(Self(problem: problem)) }
      throw CLIFailure(
        .invalidInputFile,
        CLILocalized.format("cli.record.invalid", path, problem)
      )
    }
  }

  /// Where OJD can reach the controller, in words, when the USB extension cannot claim it.
  static func usbNote(_ validated: ValidatedControllerRecord) -> String? {
    guard RecordUSBExtension(validated.record) == .doesNotClaim else { return nil }
    return CLILocalized.text(
      "cli.record.usb_not_claimed"
    )
  }
}

/// The `FILE|-` operand of `record validate` and `record install`.
private func recordFileHelp() -> ArgumentHelp {
  ArgumentHelp(
    CLILocalized.text("cli.record.file"),
    valueName: "FILE|-"
  )
}

struct RecordValidateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text(
      "cli.record.validate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.validate.discussion"
    )
  )

  @Argument(help: recordFileHelp())
  var file: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let validated = try RecordValidation.check(file, data: RecordStore.read(file))
      let result = RecordValidation(validated)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.operation ?? "", result.identity ?? "", result.family ?? "",
            result.fileName ?? "", result.transport?.rawValue ?? "",
            result.usbExtension?.rawValue ?? "",
          ]
        ])
      case .human:
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.record.validate.valid",
            file,
            validated.operation.rawValue,
            result.identity ?? "",
            validated.record.family
          )
        )
        if let note = RecordValidation.usbNote(validated) { CLIOutput.stdout(note) }
      }
    }
  }
}

struct RecordInstallCommand: AsyncParsableCommand {
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
    let installed: String
    let replaced: Bool
    let record: RecordValidation
  }

  @Argument(help: recordFileHelp())
  var file: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let data = try RecordStore.read(file)
      let validated = try RecordValidation.check(file, data: data)
      let destination = RecordStore.directory.appendingPathComponent(validated.fileName)
      let replaced = FileManager.default.fileExists(atPath: destination.path)
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
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            installed: destination.path,
            replaced: replaced,
            record: RecordValidation(validated)
          )
        )
      case .plain: CLIOutput.plain([[destination.path]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.record.install.success",
            destination.path
          )
        )
      }
      if let note = RecordValidation.usbNote(validated) { CLIOutput.stderr(note) }
    }
  }
}

struct RecordRemoveCommand: AsyncParsableCommand {
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
    let removed: String
    let dryRun: Bool
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var identity: RecordIdentity

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run")
    )
  )
  var dryRun = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let target = RecordStore.directory.appendingPathComponent(
        ControllerRecordSet.fileName(for: identity.identity)
      )
      guard FileManager.default.fileExists(atPath: target.path) else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.record.remove.not_found",
            identity.text
          )
        )
      }
      if !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format("cli.record.remove.confirm", target.path),
          force: force
        )
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
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(Result(removed: target.path, dryRun: dryRun))
      case .plain: CLIOutput.plain([[target.path]])
      case .human:
        if dryRun {
          CLIOutput.stdout(
            CLILocalized.format("cli.record.remove.dry_run", target.path)
          )
        } else {
          CLIOutput.success(
            CLILocalized.format("cli.record.remove.success", target.path)
          )
        }
      }
    }
  }
}
