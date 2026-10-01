import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ControllerCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "controller",
    abstract: CLILocalized.text(
      "cli.controller.abstract",
      "List, inspect, test, and control connected controllers."
    ),
    discussion: CLILocalized.text(
      "cli.controller.discussion",
      "CONTROLLER is an ID from 'ojd controller list', or VVVV:PPPP (hex vendor and product ID) "
        + "when exactly one connected controller has it. Every controller command needs the "
        + "service."
    ),
    subcommands: [
      ControllerListCommand.self, ControllerShowCommand.self, ControllerWatchCommand.self,
      ControllerCaptureCommand.self, ControllerRumbleCommand.self, ControllerLightCommand.self,
      ControllerPlayerCommand.self, ControllerSuspendCommand.self, ControllerResumeCommand.self,
      ControllerDisconnectCommand.self, ControllerCalibrateCommand.self, ControllerPairCommand.self,
      ControllerUnpairCommand.self,
    ]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// The shared `CONTROLLER` argument help.
let controllerArgumentHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.argument",
    "The controller: an ID from 'ojd controller list', or VVVV:PPPP."
  ),
  valueName: "controller"
)

struct ControllerListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.controller.list.abstract", "List connected controllers.")
  )

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let devices = try await ServiceConnection.request { try await $0.getStatus() }
        .connectedDevices
      let report = ControllerListReport(controllers: devices.map(ControllerSummary.init))
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain(
          report.controllers.map {
            [
              $0.id, deviceIdentity(vendorID: $0.vendorID, productID: $0.productID), $0.connection,
              $0.session, $0.name,
            ]
          }
        )
      case .human:
        guard !report.controllers.isEmpty else {
          CLIOutput.stderr(
            CLILocalized.text("cli.controller.list.empty", "No controllers are connected.")
          )
          return
        }
        let idWidth = report.controllers.map(\.id.count).max() ?? 0
        for controller in report.controllers {
          let id = controller.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
          let identity = deviceIdentity(
            vendorID: controller.vendorID,
            productID: controller.productID
          )
          let suspended =
            controller.session == ControllerSessionState.suspended.rawValue
            ? "  " + CLILocalized.text("cli.controller.list.suspended", "(suspended)") : ""
          CLIOutput.stdout(
            "\(id)  \(identity)  \(controller.connection)  \(controller.name)\(suspended)"
          )
        }
      }
    }
  }
}

struct ControllerShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.controller.show.abstract",
      "Show a controller's identity, ownership, capabilities, and virtual gamepad."
    ),
    discussion: CLILocalized.text(
      "cli.controller.show.discussion",
      "Also lists output checks: commands that exercise each rumble motor and light, with what "
        + "to observe."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  func run() async throws {
    try await global.run {
      let selector = controller
      let devices = try await ServiceConnection.request {
        try await $0.getStatus().connectedDevices
      }
      let device = try selector.resolve(in: devices)
      let record = RecordStore.load().records[
        ControllerIdentity(vendorID: device.vendorID, productID: device.productID)
      ]
      let sharesModel =
        devices.filter { $0.vendorID == device.vendorID && $0.productID == device.productID }
        .count > 1
      let report = ControllerShowReport(device, record: record, sharesModel: sharesModel)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain: CLIOutput.plain(Self.plainRows(report.controller))
      case .human: Self.printHuman(report.controller)
      }
    }
  }

  static func plainRows(_ detail: ControllerShowReport.Detail) -> [[String]] {
    var rows = [
      ["id", detail.id],
      ["identity", deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)],
      ["name", detail.name], ["connection", detail.connection], ["protocol", detail.protocol],
      ["session", detail.session], ["input-health", detail.inputHealth.state],
      ["ownership", detail.ownership.physical],
      ["controls", detail.capabilities.controls.joined(separator: ",")],
      ["rumble-motors", detail.capabilities.rumbleMotors.joined(separator: ",")],
      ["lighting", detail.capabilities.lightingFeatures.joined(separator: ",")],
    ]
    rows.append(["record", detail.record?.layer ?? "none", detail.record?.file ?? ""])
    if let virtual = detail.virtual {
      rows.append(["virtual-profile", virtual.profile ?? "", virtual.source ?? ""])
    }
    rows += detail.outputChecks.map { ["output-check", $0.id, $0.command] }
    return rows
  }

  /// The Record row: the layer and the user file, or that no record matches the model.
  private static func recordText(_ record: ControllerShowReport.Record?) -> String {
    guard let record else {
      return CLILocalized.text("cli.controller.show.record.none", "none (no record matches)")
    }
    switch record.file {
    case let file?:
      return CLILocalized.format("cli.controller.show.record.user", "your record, %@", file)
    case nil: return CLILocalized.text("cli.controller.show.record.bundled", "bundled")
    }
  }

  /// A JSON value such as `exclusiveRawUSB` in the kebab-case the other rows use:
  /// `exclusive-raw-usb`.
  static func kebabCase(_ value: String) -> String {
    var result = ""
    let characters = Array(value)
    for (index, character) in characters.enumerated() {
      if character.isUppercase, index > 0 {
        let previous = characters[index - 1]
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        if previous.isLowercase || previous.isNumber || (next?.isLowercase ?? false) {
          result.append("-")
        }
      }
      result.append(Character(character.lowercased()))
    }
    return result
  }

  private static func printHuman(_ detail: ControllerShowReport.Detail) {
    let none = CLILocalized.text("cli.controller.show.none", "none")
    func list(_ values: [String]) -> String {
      values.isEmpty ? none : values.joined(separator: ", ")
    }
    var rows: [(String, String)] = [
      (CLILocalized.text("cli.controller.show.label.name", "Name"), detail.name),
      (CLILocalized.text("cli.controller.show.label.id", "ID"), detail.id),
      (
        CLILocalized.text("cli.controller.show.label.identity", "Vendor:Product"),
        deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)
      ),
      (CLILocalized.text("cli.controller.show.label.connection", "Connection"), detail.connection),
      (CLILocalized.text("cli.controller.show.label.protocol", "Protocol"), detail.protocol),
      (CLILocalized.text("cli.controller.show.label.session", "Session"), detail.session),
      (
        CLILocalized.text("cli.controller.show.label.input", "Input"),
        detail.inputHealth.state + (detail.inputHealth.failureReason.map { " (\($0))" } ?? "")
      ),
      (
        CLILocalized.text("cli.controller.show.label.ownership", "Ownership"),
        CLILocalized.format(
          "cli.controller.show.ownership",
          "route %@, physical %@, HID input %@",
          kebabCase(detail.ownership.discoverySource),
          kebabCase(detail.ownership.physical),
          kebabCase(detail.ownership.hidInput)
        )
      ),
      (CLILocalized.text("cli.controller.show.label.record", "Record"), recordText(detail.record)),
      (
        CLILocalized.text("cli.controller.show.label.controls", "Controls"),
        list(detail.capabilities.controls)
      ),
      (
        CLILocalized.text("cli.controller.show.label.rumble", "Rumble"),
        list(detail.capabilities.rumbleMotors.map(kebabCase))
      ),
      (
        CLILocalized.text("cli.controller.show.label.lighting", "Lighting"),
        list(detail.capabilities.lightingFeatures.map(kebabCase))
      ),
    ]
    if let virtual = detail.virtual {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.label.virtual", "Virtual gamepad"),
          virtual.profile.map { "\($0) (\(virtual.source ?? ""))" } ?? none
        )
      )
    }
    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
    guard !detail.outputChecks.isEmpty else { return }
    CLIOutput.stdout("")
    CLIOutput.stdout(CLILocalized.text("cli.controller.show.label.output_checks", "Output checks"))
    for check in detail.outputChecks {
      CLIOutput.stdout("  \(check.command)")
      CLIOutput.stdout("    \(check.expected)")
    }
  }
}
