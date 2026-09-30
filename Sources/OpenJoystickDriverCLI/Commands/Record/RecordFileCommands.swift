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
        .failure,
        CLILocalized.format("cli.record.invalid", "%@ is not a valid record: %@", path, problem)
      )
    }
  }

  /// Where OJD can reach the controller, in words, when the USB extension cannot claim it.
  static func usbNote(_ validated: ValidatedControllerRecord) -> String? {
    guard RecordUSBExtension(validated.record) == .doesNotClaim else { return nil }
    return CLILocalized.text(
      "cli.record.usb_not_claimed",
      "The family uses raw USB, and the USB extension cannot claim this controller, because its "
        + "product list is signed by Apple. OJD reaches it only through direct USB access, when "
        + "macOS allows it."
    )
  }
}

/// The `FILE|-` operand of `record validate` and `record install`.
private func recordFileHelp() -> ArgumentHelp {
  ArgumentHelp(
    CLILocalized.text("cli.record.file", "A record file, or - to read the record from stdin."),
    valueName: "FILE|-"
  )
}

struct RecordValidateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: CLILocalized.text(
      "cli.record.validate.abstract",
      "Check a controller record without installing it."
    ),
    discussion: CLILocalized.text(
      "cli.record.validate.discussion",
      "Checks the record's shape, its fields against each other, and its fit with the bundled "
        + "catalog, and says whether the controller needs the USB extension. Exits 1 when the "
        + "record is invalid."
    )
  )

  @Argument(help: recordFileHelp())
  var file: String

  @OptionGroup
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
            "%@ is a valid %@ record for %@ (%@). Install it with 'ojd record install'.",
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
      "cli.record.install.abstract",
      "Check a controller record and install it for your user."
    ),
    discussion: CLILocalized.text(
      "cli.record.install.discussion",
      "Writes the record as VVVV-PPPP.json in your record directory and replaces the record "
        + "already installed for that model. The running service applies it at once. Exits 1 "
        + "and writes nothing when the record is invalid."
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    let installed: String
    let replaced: Bool
    let record: RecordValidation
  }

  @Argument(help: recordFileHelp())
  var file: String

  @OptionGroup
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
          .failure,
          CLILocalized.format(
            "cli.record.install.failed",
            "Cannot write %@: %@",
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
            "Installed %@. The running service applies it now.",
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
      "cli.record.remove.abstract",
      "Delete your controller record for one controller model."
    ),
    discussion: CLILocalized.text(
      "cli.record.remove.discussion",
      "A bundled model goes back to its bundled record. Asks for confirmation on a terminal; "
        + "needs --force otherwise."
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    let removed: String
    let dryRun: Bool
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.identity", "The controller model, as VVVV:PPPP."),
      valueName: "VVVV:PPPP"
    )
  )
  var identity: RecordIdentity

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run", "Print what would change, and change nothing.")
    )
  )
  var dryRun = false

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let target = RecordStore.directory.appendingPathComponent(
        ControllerRecordSet.fileName(for: identity.identity)
      )
      guard FileManager.default.fileExists(atPath: target.path) else {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.record.remove.not_found",
            "You have no record for %@. 'ojd record list' shows your records.",
            identity.text
          )
        )
      }
      if !dryRun {
        try CLITerminal.confirm(
          CLILocalized.format("cli.record.remove.confirm", "Delete %@?", target.path),
          force: force
        )
        do { try FileManager.default.removeItem(at: target) } catch {
          throw CLIFailure(
            .failure,
            CLILocalized.format(
              "cli.record.remove.failed",
              "Cannot delete %@: %@",
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
            CLILocalized.format("cli.record.remove.dry_run", "Would delete %@.", target.path)
          )
        } else {
          CLIOutput.success(
            CLILocalized.format("cli.record.remove.success", "Deleted %@.", target.path)
          )
        }
      }
    }
  }
}
