import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// `ojd controller lookup`: prints the address that the app's Lookup opens.
///
/// The address is for the controller's model. The command opens nothing.
struct ControllerLookupCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "lookup",
    abstract: CLILocalized.text("cli.controller.lookup.abstract"),
    discussion: CLILocalized.text("cli.controller.lookup.discussion")
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The controller model as `VVVV:PPPP`.
    let identity: String
    /// Whether a controller record exists for the model.
    let hasRecord: Bool
    /// The address Lookup opens.
    let url: String
  }

  /// The controller to look up: a connected controller, or `VVVV:PPPP` for a model that is not
  /// connected.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let model: ControllerModelID
      if case .model(let named) = controller.reference {
        model = named
      } else {
        let device = try await ServiceConnection.request { try await controller.resolve(with: $0) }
        model = ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      }
      let record = RecordStore.load().records[model]
      let result = Result(
        identity: model.description,
        hasRecord: record != nil,
        url: ControllerLookup.url(for: model, record: record).absoluteString
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain: CLIOutput.plain([[result.identity, result.url]])
      case .human: CLIOutput.stdout(result.url)
      }
    }
  }
}
