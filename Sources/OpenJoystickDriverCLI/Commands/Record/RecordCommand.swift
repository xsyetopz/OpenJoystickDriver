import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd record` command group: draft, list, check, install, test and remove controller records.
struct RecordCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "record",
    abstract: CLILocalized.text(
      "cli.record.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.group.discussion"
    ),
    subcommands: [
      RecordDraftCommand.self, RecordListCommand.self, RecordShowCommand.self,
      RecordValidateCommand.self, RecordInstallCommand.self, RecordRemoveCommand.self,
      RecordTestCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd record list` command: lists every controller record with its model, protocol family,
/// layer and file.
struct RecordListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.record.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.list.discussion"
    )
  )

  /// `--bundled`: list the bundled records alone.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.list.bundled")
    )
  )
  var bundled = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let set = bundled ? ControllerRecordSet.bundled : RecordStore.load()
      let records = set.records.values.sorted { $0.model < $1.model }.map(RecordEntry.init)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIList(items: records))
      case .plain:
        CLIOutput.plain(
          records.map {
            [
              $0.identity, CommandLineName.kebab($0.family), CommandLineName.kebab($0.layer),
              $0.file ?? "",
            ]
          }
        )
      case .human:
        let width = records.map { CommandLineName.kebab($0.family).count }.max() ?? 0
        for record in records {
          let family = CommandLineName.kebab(record.family).padding(
            toLength: width,
            withPad: " ",
            startingAt: 0
          )
          let file = record.file.map { "  \($0)" } ?? ""
          CLIOutput.stdout(
            "\(record.identity)  \(family)  \(CommandLineName.kebab(record.layer))\(file)"
          )
        }
      }
      if !bundled { RecordStore.warn(set.problems) }
    }
  }
}

/// The `ojd record show` command: prints one model's effective record and the layer of each
/// top-level field.
struct RecordShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.record.show.abstract"
    )
  )

  /// The `--json` result. `fields` maps each top-level record field to its layer.
  struct Result: Encodable, Equatable {
    /// The controller model as `VVVV:PPPP`.
    let identity: String
    /// The protocol family of the record.
    let family: String
    /// The record layer: `Bundled`, `Package` or `User`.
    let layer: String
    /// The user record file, when the record comes from one.
    let file: String?
    /// How OJD reaches the controller.
    let transport: RecordTransport
    /// Whether the DriverKit extension can claim a raw-USB controller.
    let transportClaim: RecordTransportClaim?
    /// The layer of each top-level record field.
    let fields: [String: String]
    /// The effective record.
    let record: OrderedJSON
  }

  /// The model of the record.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.record.group.identity"),
      valueName: "VVVV:PPPP"
    )
  )
  var model: ControllerModelID

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let set = RecordStore.load()
      RecordStore.warn(set.problems.filter { $0.model == model })
      guard let record = set.records[model] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format(
            "cli.record.show.notFound",
            model.description
          )
        )
      }
      let fields = record.fieldLayers.mapValues(\.rawValue)
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(
          Result(
            identity: model.description,
            family: record.family,
            layer: record.layer.rawValue,
            file: record.file?.path,
            transport: RecordTransport(record),
            transportClaim: RecordTransportClaim(record),
            fields: fields,
            record: try OrderedJSON.parse(record.document)
          )
        )
      case .plain:
        CLIOutput.plain(
          fields.sorted { $0.key < $1.key }.map { [$0.key, CommandLineName.kebab($0.value)] }
        )
      case .human:
        let file = record.file.map { " (\($0.path))" } ?? ""
        CLIOutput.stdout(
          "\(model.description)  \(CommandLineName.kebab(record.family))  "
            + "\(CommandLineName.kebab(record.layer.rawValue))\(file)"
        )
        if let note = record.bluetoothLENote { CLIOutput.stdout(note) }
        let width = fields.keys.map(\.count).max() ?? 0
        for (field, layer) in fields.sorted(by: { $0.key < $1.key }) {
          CLIOutput.stdout(
            "  \(field.padding(toLength: width, withPad: " ", startingAt: 0))  "
              + CommandLineName.kebab(layer)
          )
        }
        CLIOutput.stdout("")
        CLIOutput.raw(record.text, terminator: "")
      }
    }
  }
}
