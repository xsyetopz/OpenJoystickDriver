import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd record draft` command: reads a connected controller's HID report descriptor, captures
/// its input reports while the user presses each control, and prints a record to start from.
struct RecordDraftCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "draft",
    abstract: CLILocalized.text(
      "cli.record.draft.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.record.draft.discussion"
    )
  )

  /// The `--json` result. `report` is absent when nothing chose an input report.
  struct Result: Encodable, Equatable {
    /// The input report that the draft maps.
    struct Report: Encodable, Equatable {
      /// The report ID, or nil when the controller uses no report IDs.
      let id: Int?
      /// The report length in bytes.
      let length: Int
    }

    /// The controller model as `VVVV:PPPP`.
    let identity: String
    /// The controller name.
    let name: String
    /// Whether the draft is a `Controller` for a model without a bundled record, or a
    /// `ControllerPatch`.
    let operation: String
    /// The protocol family of the draft.
    let family: String
    /// The input report that the draft maps.
    let report: Report?
    /// The number of input reports captured.
    let capturedReports: Int
    /// The bytes that changed during the capture, with their smallest and largest values.
    let changedBytes: [ControllerRecordDraft.ChangedByte]
    /// The drafted record.
    let record: OrderedJSON
  }

  /// Reads the report descriptor of a connected controller model; tests replace it.
  @TaskLocal
  static var descriptor: @Sendable (_ vendorID: Int, _ productID: Int) -> [UInt8]? = {
    PlatformHosts.current.physicalReportDescriptor(vendorID: $0, productID: $1)
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to draft a record for.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--duration`: how many seconds to capture input reports.
  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.record.draft.duration"
      ),
      valueName: "seconds"
    )
  )
  var duration: Double = 10

  /// Checks the duration.
  func validate() throws { try validateDuration(duration) }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await withController(controller) { client, device in
        if CLIContext.current.format == .human {
          CLIOutput.success(
            CLILocalized.format(
              "cli.record.draft.started",
              device.name,
              device.identity
            )
          )
        }
        let reports = try await capture(client, device)
        let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
        guard
          let draft = ControllerRecordDraft(
            model: model,
            bundled: ControllerRecordSet.bundled.records[model] != nil,
            descriptor: Self.descriptor(Int(device.vendorID), Int(device.productID)),
            reports: reports
          )
        else {
          throw CLIFailure(
            .controllerRequestFailed,
            CLILocalized.format(
              "cli.record.draft.noLayout",
              device.identity,
              device.identity
            )
          )
        }
        try print(draft, device)
      }
    }
  }

  /// The input reports the controller sends during `duration`, in order.
  private func capture(
    _ client: ApplicationServiceClient,
    _ device: ApplicationServiceDeviceDescription
  ) async throws -> [[UInt8]] {
    let timeout = CLIContext.current.requestTimeout
    let read: @Sendable () async throws -> [PacketLogEntry] = {
      try await ServiceConnection.withDeadline(seconds: timeout) {
        try await client.packetLog(for: .session(device.sessionToken))
      }
    }
    var cursor = PacketLogSnapshotCursor(snapshot: try await read())
    var reports: [[UInt8]] = []
    _ = try await pollController(duration: duration) {
      for entry in cursor.consume(snapshot: try await read()) where entry.direction == .received {
        reports.append(entry.reportBytes)
      }
      return false
    }
    return reports
  }

  /// Prints the draft as JSON, as the changed bytes in `--plain` rows, or as text with the record.
  private func print(
    _ draft: ControllerRecordDraft,
    _ device: ApplicationServiceDeviceDescription
  ) throws {
    let changed = draft.changedBytes
    switch CLIContext.current.format {
    case .json:
      try CLIOutput.json(
        Result(
          identity: device.identity,
          name: device.name,
          operation: draft.operation.rawValue,
          family: draft.family.rawValue,
          report: draft.reportLength.map {
            Result.Report(id: draft.reportID.map(Int.init), length: $0)
          },
          capturedReports: draft.capturedReports,
          changedBytes: changed,
          record: try OrderedJSON.parse(draft.document)
        )
      )
    case .plain:
      CLIOutput.plain(changed.map { [$0.byte, $0.minimum, $0.maximum].map(String.init) })
    case .human:
      CLIOutput.raw(draft.text, terminator: "")
      CLIOutput.success(
        CLILocalized.format(
          "cli.record.draft.captured",
          draft.capturedReports
        )
      )
      for byte in changed {
        CLIOutput.success(
          CLILocalized.format(
            "cli.record.draft.changedByte",
            byte.byte,
            byte.minimum,
            byte.maximum
          )
        )
      }
      CLIOutput.success(
        CLILocalized.text(
          "cli.record.draft.next"
        )
      )
    }
  }
}
