import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ControllerCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "controller",
    abstract: CLILocalized.text(
      "cli.controller.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.controller.discussion.unit"
      ),
    subcommands: [
      ControllerListCommand.self, ControllerShowCommand.self, ControllerWatchCommand.self,
      ControllerCaptureCommand.self, ControllerRumbleCommand.self, ControllerLightCommand.self,
      ControllerPlayerCommand.self, ControllerSuspendCommand.self, ControllerResumeCommand.self,
      ControllerDisconnectCommand.self, ControllerCalibrateCommand.self, ControllerPairCommand.self,
      ControllerUnpairCommand.self,
    ]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The shared `CONTROLLER` argument help.
let controllerArgumentHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.argument"
  ),
  valueName: "controller"
)

struct ControllerListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.controller.list.abstract")
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

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
              $0.session, $0.name, $0.unit ?? "", $0.power?.battery.percentageText ?? "",
              $0.power?.charging.rawValue ?? "",
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
          CLIOutput.stdout(
            "\(id)  \(unit)\(identity)  \(controller.connection)  \(battery)\(controller.name)"
              + suspended
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
      "cli.controller.show.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.show.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
    var rows = [["id", detail.id]]
    if let unit = detail.unit { rows.append(["unit", unit]) }
    rows += [
      ["identity", deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)],
      ["name", detail.name], ["connection", detail.connection], ["protocol", detail.protocol],
      ["session", detail.session],
    ]
    if let power = detail.power {
      rows.append([
        "power", power.charging.rawValue, power.battery.percentageText ?? "",
        power.wiredPower.map(String.init) ?? "",
      ])
    }
    rows += [
      ["input-health", detail.inputHealth.state],
      ["ownership", detail.ownership.physical],
      ["controls", detail.capabilities.controls.joined(separator: ",")],
      ["rumble-motors", detail.capabilities.rumbleMotors.joined(separator: ",")],
      ["lighting", detail.capabilities.lightingFeatures.joined(separator: ",")],
      ["output-owner", detail.capabilities.outputOwner],
    ]
    rows.append(["record", detail.record?.layer ?? "none", detail.record?.file ?? ""])
    if let tuning = detail.tuning { rows.append(["tuning"] + tuning.rows) }
    if let virtual = detail.virtual {
      rows.append(["virtual-profile", virtual.profile ?? "", virtual.source ?? ""])
    }
    if let publication = detail.publication {
      rows.append(["publication", publication.state, publication.reason ?? ""])
    }
    rows += detail.outputChecks.map { ["output-check", $0.id, $0.command] }
    return rows
  }

  /// The Record row: the layer and the user file, or that no record matches the model.
  private static func recordText(_ record: ControllerShowReport.Record?) -> String {
    guard let record else {
      return CLILocalized.text("cli.controller.show.record.none")
    }
    switch record.file {
    case let file?:
      return CLILocalized.format("cli.controller.show.record.user", file)
    case nil: return CLILocalized.text("cli.controller.show.record.bundled")
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
    let none = CLILocalized.text("cli.controller.show.none")
    func list(_ values: [String]) -> String {
      values.isEmpty ? none : values.joined(separator: ", ")
    }
    var rows: [(String, String)] = [
      (CLILocalized.text("cli.controller.show.label.name"), detail.name),
      (CLILocalized.text("cli.controller.show.label.id"), detail.id),
      (CLILocalized.text("cli.controller.show.label.unit"), detail.unit ?? none),
      (
        CLILocalized.text("cli.controller.show.label.identity"),
        deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)
      ),
      (CLILocalized.text("cli.controller.show.label.connection"), detail.connection),
      (CLILocalized.text("cli.controller.show.label.protocol"), detail.protocol),
      (CLILocalized.text("cli.controller.show.label.session"), detail.session),
    ]
    if let power = detail.power {
      let charging = power.charging == .unknown ? "" : " (\(power.charging.rawValue))"
      rows.append(
        (
          CLILocalized.text("cli.controller.show.label.battery"),
          (power.battery.percentageText ?? none) + charging
        )
      )
    }
    rows += [
      (
        CLILocalized.text("cli.controller.show.label.input"),
        detail.inputHealth.state + (detail.inputHealth.failureReason.map { " (\($0))" } ?? "")
      ),
      (
        CLILocalized.text("cli.controller.show.label.ownership"),
        CLILocalized.format(
          "cli.controller.show.ownership",
          kebabCase(detail.ownership.discoverySource),
          kebabCase(detail.ownership.physical),
          kebabCase(detail.ownership.hidInput)
        )
      ),
      (CLILocalized.text("cli.controller.show.label.record"), recordText(detail.record)),
      (
        CLILocalized.text("cli.controller.show.label.controls"),
        list(detail.capabilities.controls)
      ),
      (
        CLILocalized.text("cli.controller.show.label.rumble"),
        list(detail.capabilities.rumbleMotors.map(kebabCase))
      ),
      (
        CLILocalized.text("cli.controller.show.label.lighting"),
        list(detail.capabilities.lightingFeatures.map(kebabCase))
      ),
    ]
    // The output lists above hold only what macOS leaves undone, so say why.
    if detail.capabilities.outputOwner == ControllerOwnership.macOS.rawValue {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.label.output_owner"),
          CLILocalized.text("cli.controller.show.output_owner.macos")
        )
      )
    }
    if let tuning = detail.tuning {
      rows.append(
        (CLILocalized.text("cli.controller.show.label.tuning"), tuning.rows.joined(separator: ", "))
      )
    }
    if let virtual = detail.virtual {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.label.virtual"),
          virtual.profile.map { "\($0) (\(virtual.source ?? ""))" } ?? none
        )
      )
    }
    if let publication = detail.publication {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.label.publication"),
          publication.state + (publication.reason.map { " (\($0))" } ?? "")
        )
      )
    }
    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
    guard !detail.outputChecks.isEmpty else { return }
    CLIOutput.stdout("")
    CLIOutput.stdout(CLILocalized.text("cli.controller.show.label.output_checks"))
    for check in detail.outputChecks {
      CLIOutput.stdout("  \(check.command)")
      CLIOutput.stdout("    \(check.expected)")
    }
  }
}
