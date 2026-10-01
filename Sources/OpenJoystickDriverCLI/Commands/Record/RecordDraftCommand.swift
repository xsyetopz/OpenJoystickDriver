import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct RecordDraftCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "draft",
    abstract: CLILocalized.text(
      "cli.record.draft.abstract",
      "Draft a controller record from a connected controller."
    ),
    discussion: CLILocalized.text(
      "cli.record.draft.discussion",
      "Reads the controller's HID report descriptor and captures its input reports while you "
        + "press each control, then prints a record to start from. The record maps the buttons, "
        + "sticks, triggers, and hat the descriptor states plainly. The bytes that changed "
        + "during the capture show where the other controls sit. Needs the service."
    )
  )

  /// The `--json` result. `report` is absent when nothing chose an input report.
  struct Result: Encodable, Equatable {
    struct Report: Encodable, Equatable {
      let id: Int?
      let length: Int
    }

    let identity: String
    let name: String
    let operation: String
    let family: String
    let report: Report?
    let capturedReports: Int
    let changedBytes: [ControllerRecordDraft.ChangedByte]
    let record: RecordJSON
  }

  /// Reads the report descriptor of a connected controller model; tests replace it.
  @TaskLocal
  static var descriptor: @Sendable (_ vendorID: Int, _ productID: Int) -> [UInt8]? = {
    HIDDescriptorReportFormat.copyPhysicalReportDescriptor(vendorID: $0, productID: $1)
  }

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.record.draft.duration",
        "Capture input reports for this many seconds."
      ),
      valueName: "seconds"
    )
  )
  var duration: Double = 10

  func validate() throws { try validateDuration(duration) }

  func run() async throws {
    try await global.run {
      try await withController(controller) { client, device in
        if CLIContext.current.format == .human {
          CLIOutput.success(
            CLILocalized.format(
              "cli.record.draft.started",
              "Press every control on %@ (%@), and move each stick and trigger.",
              device.name,
              device.identity
            )
          )
        }
        let reports = try await capture(client, device)
        let identity = ControllerIdentity(vendorID: device.vendorID, productID: device.productID)
        guard
          let draft = ControllerRecordDraft(
            identity: identity,
            bundled: ControllerRecordSet.bundled.records[identity] != nil,
            descriptor: Self.descriptor(Int(device.vendorID), Int(device.productID)),
            reports: reports
          )
        else {
          throw CLIFailure(
            .failure,
            CLILocalized.format(
              "cli.record.draft.no_layout",
              "No control of %@ could be read from its HID report descriptor, and its bundled "
                + "record already names its family. 'ojd record show %@' shows that record.",
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
        try await client.packetLog(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
      }
    }
    var cursor = PacketLogSnapshotCursor(snapshot: try await read())
    var reports: [[UInt8]] = []
    _ = try await pollController(duration: duration) {
      for entry in cursor.consume(snapshot: try await read()) where entry.direction == .received {
        reports.append(entry.hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
      }
      return false
    }
    return reports
  }

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
          record: try RecordJSON(data: draft.document)
        )
      )
    case .plain:
      CLIOutput.plain(changed.map { [$0.byte, $0.minimum, $0.maximum].map(String.init) })
    case .human:
      CLIOutput.stdout(String(bytes: draft.document, encoding: .utf8) ?? "")
      CLIOutput.success(
        CLILocalized.format(
          "cli.record.draft.captured",
          "Input reports captured: %lld.",
          draft.capturedReports
        )
      )
      for byte in changed {
        CLIOutput.success(
          CLILocalized.format(
            "cli.record.draft.changed_byte",
            "Byte %lld changed: %lld to %lld.",
            byte.byte,
            byte.minimum,
            byte.maximum
          )
        )
      }
      CLIOutput.success(
        CLILocalized.text(
          "cli.record.draft.next",
          "Save the record to a file, check each control, then run 'ojd record validate FILE'."
        )
      )
    }
  }
}
