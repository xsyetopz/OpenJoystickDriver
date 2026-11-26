import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd controller` command group: list, inspect, watch and test the connected controllers.
struct ControllerCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "controller",
    abstract: CLILocalized.text(
      "cli.controller.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.group.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.controller.group.discussionUnit"
      ),
    subcommands: [
      ControllerListCommand.self, ControllerShowCommand.self, ControllerWatchCommand.self,
      ControllerCheckCommand.self, ControllerCaptureCommand.self, ControllerSendCommand.self,
      ControllerRumbleCommand.self, ControllerLightCommand.self,
      ControllerPlayerCommand.self, ControllerSpeakerCommand.self, ControllerSuspendCommand.self,
      ControllerResumeCommand.self,
      ControllerDisconnectCommand.self, ControllerCalibrateCommand.self, ControllerPairCommand.self,
      ControllerUnpairCommand.self, ControllerClaimCommand.self,
      ControllerReleaseCommand.self, ControllerLookupCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The shared help of the `CONTROLLER` argument.
let controllerArgumentHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.group.argument"
  ),
  valueName: "controller"
)

/// The `ojd controller list` command: prints the connected controllers.
struct ControllerListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.controller.list.abstract")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let devices = try await ServiceConnection.request { try await $0.getStatus() }
        .connectedDevices
      let report = CLIList(items: devices.map(ControllerSummary.init))
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain(
          report.items.map {
            [
              $0.id, deviceIdentity(vendorID: $0.vendorID, productID: $0.productID), $0.connection,
              CommandLineName.kebab($0.session), $0.name, $0.unit ?? "",
              $0.ownedByAnotherClient ? "owned-by-another-client" : "",
              $0.owner.map { $0.processID.map { "\($0)" } ?? "" } ?? "", $0.owner?.name ?? "",
              $0.power?.battery.percentageText ?? "",
              $0.power.map { CommandLineName.kebab($0.charging.rawValue) } ?? "",
              $0.alsoListedBySystem ? "also-listed-by-system" : "",
              $0.waitsForGuidePress ? "waits-for-guide-press" : "",
            ]
          }
        )
      case .human:
        guard !report.items.isEmpty else {
          CLIOutput.stderr(
            CLILocalized.text("cli.controller.list.empty")
          )
          return
        }
        let idWidth = report.items.map(\.id.count).max() ?? 0
        let unitWidth = report.items.map { $0.unit?.count ?? 0 }.max() ?? 0
        let batteryWidth =
          report.items.map { $0.power?.battery.percentageText?.count ?? 0 }.max() ?? 0
        for controller in report.items {
          let id = controller.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
          let unit =
            unitWidth == 0
            ? ""
            : (controller.unit ?? "").padding(toLength: unitWidth, withPad: " ", startingAt: 0)
              + "  "
          let identity = deviceIdentity(
            vendorID: controller.vendorID,
            productID: controller.productID
          )
          let battery =
            batteryWidth == 0
            ? ""
            : (controller.power?.battery.percentageText ?? "")
              .padding(toLength: batteryWidth, withPad: " ", startingAt: 0) + "  "
          let suspended =
            controller.session == ControllerSessionState.suspended.rawValue
            ? "  " + CLILocalized.text("cli.controller.list.suspended") : ""
          let held =
            controller.ownedByAnotherClient
            ? "  "
              + USBExclusiveOwner.heldMessage(for: controller.owner, localize: CLILocalized.text)
            : ""
          let listed =
            controller.alsoListedBySystem
            ? "  " + CLILocalized.text("status.controllerAlsoListedBySystem") : ""
          let guide =
            controller.waitsForGuidePress
            ? "  " + CLILocalized.text("cli.controller.list.pressGuide") : ""
          CLIOutput.stdout(
            "\(id)  \(unit)\(identity)  \(controller.connection)  \(battery)\(controller.name)"
              + suspended + held + listed + guide
          )
        }
      }
    }
  }
}
