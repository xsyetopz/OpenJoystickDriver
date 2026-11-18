import Foundation
import OpenJoystickDriverKit

/// What `ojd controller claim` and `ojd controller release` share: they set `server` in the user
/// record of the controller's model and print the same result.
enum ControllerServerChange {
  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The session ID of the controller.
    let controller: String
    /// The controller model as `VVVV:PPPP`.
    let identity: String
    /// The `server` value after the command.
    let server: ControllerServer
    /// The `server` value before the command.
    let previous: ControllerServer
    /// The path of the record file that the command writes.
    let file: String
    /// Whether the file does not exist before the command.
    let created: Bool
    /// Whether `--dry-run` is set, so nothing is written.
    let dryRun: Bool
  }

  /// Sets `server` for the model of the controller that `selector` names, and prints the result.
  ///
  /// A claim of a model that Apple's driver holds sends the extension activation request instead
  /// and prints its state, because only the extension can take the controller from Apple's driver.
  ///
  /// - Throws: ``CLIFailure`` when the controller is not found, its model cannot change hands, the
  ///   record is not valid, or the file cannot be written.
  static func run(
    _ server: ControllerServer,
    controller selector: ControllerSelector,
    dryRun: Bool,
    global: GlobalOptions
  ) async throws {
    try await global.run {
      let device = try await ServiceConnection.request { try await selector.resolve(with: $0) }
      if server == .ojd, device.isHeldByAppleDriver {
        try await submitTransportExtension(
          .activate,
          done: .active,
          message: CLILocalized.text("cli.transportExtension.group.activated")
        )
        return
      }
      let model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      let records = RecordStore.load()
      try checkSupported(
        device,
        server: records.records[model]?.server ?? .system,
        accessRoute: records.records[model]?.accessRoute ?? .system
      )
      let change = try change(model, to: server, records: records, device: device)
      if !dryRun { try write(change) }
      let result = Result(
        controller: device.sessionToken.rawValue,
        identity: device.identity,
        server: server,
        previous: change.previousServer,
        file: change.file.path,
        created: change.created,
        dryRun: dryRun
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [result.identity, CommandLineName.kebab(result.server.rawValue), result.file]
        ])
      case .human:
        let removal = change.data == nil
        if dryRun {
          CLIOutput.stdout(
            removal
              ? CLILocalized.format(
                "cli.controller.group.serverRemovedDryRun",
                result.identity,
                result.file
              )
              : CLILocalized.format(
                "cli.controller.group.serverDryRun",
                result.identity,
                CommandLineName.kebab(result.server.rawValue),
                result.file
              )
          )
        } else {
          CLIOutput.success(
            removal
              ? CLILocalized.format(
                "cli.controller.group.serverRemoved",
                result.identity,
                result.file
              )
              : CLILocalized.format(
                "cli.controller.group.serverSuccess",
                result.identity,
                CommandLineName.kebab(result.server.rawValue),
                result.file
              )
          )
        }
      }
    }
  }

  /// Refuses a controller whose model cannot change hands: a raw-USB family, which OJD always
  /// owns, or a model macOS does not serve natively.
  ///
  /// A model whose record already gives it to OJD counts as native, because OJD seized a controller
  /// macOS would serve.
  static func checkSupported(
    _ device: ApplicationServiceDeviceDescription,
    server: ControllerServer,
    accessRoute: ControllerAccessRoute
  ) throws {
    var input = ServingInput(device)
    input.server = server
    input.accessRoute = accessRoute
    if accessRoute != .system {
      throw CLIFailure(
        .claimUnsupported,
        CLILocalized.format("cli.controller.group.serverRawUsb", device.identity)
      )
    }
    guard ServingPolicy.offersServerChoice(input) else {
      throw CLIFailure(
        .claimUnsupported,
        CLILocalized.format("platform.macos.cli.controller.group.serverNotNative", device.identity)
      )
    }
  }

  /// The change to the user record that sets `server`, before it is written.
  private static func change(
    _ model: ControllerModelID,
    to server: ControllerServer,
    records: ControllerRecordSet,
    device: ApplicationServiceDeviceDescription
  ) throws -> ControllerRecordWriter.Change {
    do {
      return try ControllerRecordWriter.change(
        server,
        for: model,
        records: records,
        directory: RecordStore.directory
      )
    } catch {
      switch error {
      case .noRecord:
        throw CLIFailure(
          .claimUnsupported,
          CLILocalized.format(
            "cli.controller.group.serverNoRecord",
            device.identity,
            device.identity
          )
        )
      case .invalidFile(let problem), .invalidResult(let problem):
        throw CLIFailure(
          .invalidInputFile,
          CLILocalized.format(
            "cli.controller.group.serverInvalid",
            RecordStore.directory.appendingPathComponent(
              ControllerRecordSet.fileName(for: model)
            ).path,
            problem
          )
        )
      }
    }
  }

  /// Writes `change` to disk.
  ///
  /// - Throws: ``CLIFailure`` with `fileAccessFailed` when the file cannot be written.
  private static func write(_ change: ControllerRecordWriter.Change) throws {
    do { try ControllerRecordWriter.write(change) } catch {
      throw CLIFailure(
        .fileAccessFailed,
        CLILocalized.format(
          "cli.record.install.failed",
          change.file.path,
          error.localizedDescription
        )
      )
    }
  }
}
