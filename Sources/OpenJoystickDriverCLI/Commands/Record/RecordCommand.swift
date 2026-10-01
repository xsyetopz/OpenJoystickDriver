import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct RecordCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "record",
    abstract: CLILocalized.text(
      "cli.record.abstract",
      "Draft, list, check, install, or remove controller records."
    ),
    discussion: CLILocalized.text(
      "cli.record.discussion",
      "A controller record tells OpenJoystickDriver how to drive one controller model. Your "
        + "records live in ~/Library/Application Support/OpenJoystickDriver/Controllers and "
        + "add a model or patch a bundled one. The running service applies them when the "
        + "directory changes. Only 'ojd record draft' needs the service."
    ),
    subcommands: [
      RecordDraftCommand.self, RecordListCommand.self, RecordShowCommand.self,
      RecordValidateCommand.self, RecordInstallCommand.self, RecordRemoveCommand.self,
    ]
  )

  @OptionGroup
  var global: GlobalOptions
}

struct RecordListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.record.list.abstract",
      "List every controller record and the layer it comes from."
    ),
    discussion: CLILocalized.text(
      "cli.record.list.discussion",
      "Lists the bundled records with your records applied, and names each file OJD skipped "
        + "and why."
    )
  )

  /// The `--json` result. `skipped` is absent with `--bundled`.
  struct Result: Encodable, Equatable {
    let records: [RecordEntry]
    let skipped: [SkippedRecord]?
  }

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.list.bundled", "List the bundled catalog alone.")
    )
  )
  var bundled = false

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let set = bundled ? ControllerRecordSet.bundled : RecordStore.load()
      let records = set.records.values.sorted {
        ($0.identity.vendorID, $0.identity.productID) < (
          $1.identity.vendorID, $1.identity.productID
        )
      }.map(RecordEntry.init)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(records: records, skipped: bundled ? nil : set.problems.map(SkippedRecord.init))
        )
      case .plain:
        CLIOutput.plain(records.map { [$0.identity, $0.family, $0.layer, $0.file ?? ""] })
      case .human:
        let width = records.map(\.family.count).max() ?? 0
        for record in records {
          let family = record.family.padding(toLength: width, withPad: " ", startingAt: 0)
          let file = record.file.map { "  \($0)" } ?? ""
          CLIOutput.stdout("\(record.identity)  \(family)  \(record.layer)\(file)")
        }
      }
      if !bundled { RecordStore.warn(set.problems) }
    }
  }
}

struct RecordShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.record.show.abstract",
      "Show the effective record of one controller model and the layer of each part."
    )
  )

  /// The `--json` result. `fields` maps each top-level record field to its layer.
  struct Result: Encodable, Equatable {
    let identity: String
    let family: String
    let layer: String
    let file: String?
    let transport: RecordTransport
    let usbExtension: RecordUSBExtension?
    let fields: [String: String]
    let record: RecordJSON
  }

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.identity", "The controller model, as VVVV:PPPP."),
      valueName: "VVVV:PPPP"
    )
  )
  var identity: RecordIdentity

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.identity == identity.identity })
      guard let record = set.records[identity.identity] else {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.record.show.not_found",
            "No controller record for %@. 'ojd record list' shows every record.",
            identity.text
          )
        )
      }
      let fields = record.fieldLayers.mapValues(\.rawValue)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            identity: identity.text,
            family: record.family,
            layer: record.layer.rawValue,
            file: record.userFile?.path,
            transport: RecordTransport(record),
            usbExtension: RecordUSBExtension(record),
            fields: fields,
            record: try RecordJSON(data: record.document)
          )
        )
      case .plain: CLIOutput.plain(fields.sorted { $0.key < $1.key }.map { [$0.key, $0.value] })
      case .human:
        let file = record.userFile.map { " (\($0.path))" } ?? ""
        CLIOutput.stdout("\(identity.text)  \(record.family)  \(record.layer.rawValue)\(file)")
        let width = fields.keys.map(\.count).max() ?? 0
        for (field, layer) in fields.sorted(by: { $0.key < $1.key }) {
          CLIOutput.stdout(
            "  \(field.padding(toLength: width, withPad: " ", startingAt: 0))  \(layer)"
          )
        }
        CLIOutput.stdout("")
        CLIOutput.stdout(String(bytes: record.document, encoding: .utf8) ?? "")
      }
    }
  }
}
