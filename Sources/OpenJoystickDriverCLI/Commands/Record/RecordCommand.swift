import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct RecordCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "record",
    abstract: CLILocalized.text(
      "cli.record.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.discussion"
    ),
    subcommands: [
      RecordDraftCommand.self, RecordListCommand.self, RecordShowCommand.self,
      RecordValidateCommand.self, RecordInstallCommand.self, RecordRemoveCommand.self,
      RecordTestCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct RecordListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.record.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.list.discussion"
    )
  )

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.list.bundled")
    )
  )
  var bundled = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
        try CLIOutput.json(CLIList(items: records))
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
      "cli.record.show.abstract"
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
      CLILocalized.text("cli.record.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var identity: RecordIdentity

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.identity == identity.identity })
      guard let record = set.records[identity.identity] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.record.show.not_found",
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
        if let note = RecordValidation.bluetoothLENote(record) { CLIOutput.stdout(note) }
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
