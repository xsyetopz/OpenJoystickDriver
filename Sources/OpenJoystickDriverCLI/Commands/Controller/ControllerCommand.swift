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
      ControllerCaptureCommand.self, ControllerRumbleCommand.self, ControllerLightCommand.self,
      ControllerPlayerCommand.self, ControllerSpeakerCommand.self, ControllerSuspendCommand.self,
      ControllerResumeCommand.self,
      ControllerDisconnectCommand.self, ControllerCalibrateCommand.self, ControllerPairCommand.self,
      ControllerUnpairCommand.self, ControllerClaimCommand.self,
      ControllerReleaseCommand.self,
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

/// The `ojd controller show` command: prints one controller's identity, ownership, capabilities,
/// effective record and virtual gamepad.
struct ControllerShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.controller.show.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.show.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to show.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let devices = try await ServiceConnection.request {
        try await $0.getStatus().connectedDevices
      }
      let device = try selector.resolve(in: devices)
      let record = RecordStore.load().records[
        ControllerModelID(vendorID: device.vendorID, productID: device.productID)
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

  /// The `--plain` rows of `controller show`, one per field.
  static func plainRows(_ detail: ControllerShowReport.Detail) -> [[String]] {
    var rows = [["id", detail.id]]
    if let unit = detail.unit { rows.append(["unit", unit]) }
    rows += [
      ["identity", deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)],
      ["name", detail.name], ["connection", detail.connection],
      ["protocol", detail.protocol.commandLineName],
      ["session", CommandLineName.kebab(detail.session)],
    ]
    if let power = detail.power {
      rows.append([
        "power", CommandLineName.kebab(power.charging.rawValue), power.battery.percentageText ?? "",
        power.wiredPower.map(String.init) ?? "",
      ])
    }
    if let wii = detail.wiiRemote {
      let motionPlus =
        wii.motionPlusActive ? (wii.isGyroRestReady ? "ready" : "calibrating") : "off"
      rows += [
        ["report-mode", wii.reportModeText],
        ["extension", wii.extensionKind.map { CommandLineName.kebab($0.rawValue) } ?? ""],
        ["unknown-extension-id", wii.unknownExtensionID ?? ""],
        ["motion-plus", motionPlus],
      ]
    }
    rows += [
      ["input-health", CommandLineName.kebab(detail.inputHealth.state)],
      ["ownership", CommandLineName.kebab(detail.ownership.physical)],
      [
        "server", CommandLineName.kebab(detail.ownership.server.rawValue),
        CommandLineName.kebab(detail.ownership.serverSource),
      ],
      [
        "serving-route", CommandLineName.kebab(detail.serving.route),
        detail.serving.reason.map(CommandLineName.kebab) ?? "",
      ],
      ["persona", detail.serving.persona.map(CommandLineName.kebab) ?? ""],
    ]
    if detail.serving.heldByAppleDriver == true { rows.append(["served-by", "macos"]) }
    rows += [
      ["controls", detail.capabilities.controls.map(CommandLineName.kebab).joined(separator: ",")],
      [
        "rumble-motors",
        detail.capabilities.rumbleMotors.map(CommandLineName.kebab).joined(separator: ","),
      ],
      [
        "lighting",
        detail.capabilities.lightingFeatures.map(CommandLineName.kebab).joined(separator: ","),
      ],
      ["output-owner", CommandLineName.kebab(detail.capabilities.outputOwner)],
    ]
    rows.append([
      "record", detail.record.map { CommandLineName.kebab($0.layer) } ?? "none",
      detail.record?.file ?? "",
    ])
    if let mapping = detail.inputMapping {
      rows.append(["input-mapping"] + mapping.plainFields)
    }
    if let tuning = detail.tuning { rows.append(["tuning"] + tuning.rows) }
    if let virtual = detail.virtual {
      rows.append([
        "virtual-profile", virtual.profile.map(CommandLineName.kebab) ?? "",
        virtual.source.map { CommandLineName.kebab($0.rawValue) } ?? "",
      ])
    }
    if let publication = detail.publication {
      rows.append([
        "publication", CommandLineName.kebab(publication.state),
        publication.reason.map(CommandLineName.kebab) ?? publication.failure ?? "",
      ])
    }
    rows += detail.outputChecks.map { ["output-check", $0.id, $0.command] }
    return rows
  }

  /// The Record row: the layer and the user file, or that no record matches the model.
  private static func recordText(_ record: ControllerShowReport.Record?) -> String {
    guard let record else {
      return CLILocalized.text("cli.controller.show.recordNone")
    }
    switch record.file {
    case let file?:
      return CLILocalized.format("cli.controller.show.recordUser", file)
    case nil: return CLILocalized.text("cli.controller.show.recordBundled")
    }
  }

  /// Prints the labelled rows of `controller show` for people.
  private static func printHuman(_ detail: ControllerShowReport.Detail) {
    let none = CLILocalized.text("cli.controller.show.none")
    func list(_ values: [String]) -> String {
      values.isEmpty ? none : values.joined(separator: ", ")
    }
    var rows: [(String, String)] = [
      (CLILocalized.text("cli.controller.show.labelName"), detail.name),
      (CLILocalized.text("cli.controller.show.labelId"), detail.id),
      (CLILocalized.text("cli.controller.show.labelUnit"), detail.unit ?? none),
      (
        CLILocalized.text("cli.controller.show.labelIdentity"),
        deviceIdentity(vendorID: detail.vendorID, productID: detail.productID)
      ),
      (CLILocalized.text("cli.controller.show.labelConnection"), detail.connection),
      (
        CLILocalized.text("cli.controller.show.labelProtocol"),
        detail.protocol.commandLineName
      ),
      (
        CLILocalized.text("cli.controller.show.labelSession"),
        CommandLineName.kebab(detail.session)
      ),
    ]
    if let power = detail.power {
      let charging =
        power.charging == .unknown ? "" : " (\(CommandLineName.kebab(power.charging.rawValue)))"
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelBattery"),
          (power.battery.percentageText ?? none) + charging
        )
      )
    }
    if let wii = detail.wiiRemote {
      rows += [
        (CLILocalized.text("cli.controller.show.labelReportMode"), wii.reportModeText),
        (CLILocalized.text("cli.controller.show.labelExtension"), wii.extensionText()),
        (CLILocalized.text("cli.controller.show.labelMotionPlus"), wii.motionPlusText()),
      ]
    }
    // A controller that another client holds runs no input session, so it has no input health.
    if detail.ownership.hidInput != HIDInputOwnership.ownedByAnotherClient.rawValue {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelInput"),
          CommandLineName.kebab(detail.inputHealth.state)
            + (detail.inputHealth.failureReason.map { " (\(CommandLineName.kebab($0)))" } ?? "")
        )
      )
    }
    rows += [
      (
        CLILocalized.text("cli.controller.show.labelOwnership"),
        CLILocalized.format(
          "cli.controller.show.ownership",
          CommandLineName.kebab(detail.ownership.discoverySource),
          CommandLineName.kebab(detail.ownership.physical),
          CommandLineName.kebab(detail.ownership.hidInput)
        )
      ),
      (
        CLILocalized.text("cli.controller.show.labelServer"),
        CLILocalized.format(
          "cli.controller.show.server",
          detail.ownership.server.rawValue,
          CommandLineName.kebab(detail.ownership.serverSource)
        )
      ),
      (
        CLILocalized.text("cli.controller.show.labelServing"),
        CommandLineName.kebab(detail.serving.route)
          + (detail.serving.reason.map { " (\(CommandLineName.kebab($0)))" } ?? "")
      ),
      (
        CLILocalized.text("cli.controller.show.labelPersona"),
        detail.serving.persona.map(CommandLineName.kebab) ?? none
      ),
      (CLILocalized.text("cli.controller.show.labelRecord"), recordText(detail.record)),
    ]
    if detail.serving.heldByAppleDriver == true {
      rows.append(
        (
          CLILocalized.text("platform.macos.cli.controller.show.labelServedBy"),
          CLILocalized.format("platform.macos.cli.controller.show.servedByMacOS", detail.id)
        )
      )
    }
    if let mapping = detail.inputMapping {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelInputMapping"),
          mapping.rowText(localize: CLILocalized.text)
        )
      )
      if !mapping.unmapped.isEmpty {
        rows.append(
          (
            CLILocalized.text("cli.controller.show.labelUnmapped"),
            mapping.unmapped.joined(separator: ", ")
          )
        )
      }
    }
    rows += [
      (
        CLILocalized.text("cli.controller.show.labelControls"),
        list(detail.capabilities.controls.map(CommandLineName.kebab))
      ),
      (
        CLILocalized.text("cli.controller.show.labelRumble"),
        list(detail.capabilities.rumbleMotors.map(CommandLineName.kebab))
      ),
      (
        CLILocalized.text("cli.controller.show.labelLighting"),
        list(detail.capabilities.lightingFeatures.map(CommandLineName.kebab))
      ),
    ]
    if detail.ownership.hidInput == HIDInputOwnership.ownedByAnotherClient.rawValue {
      rows.append(
        (
          CLILocalized.text("ui.controllers.exclusiveOwner"),
          USBExclusiveOwner.heldMessage(for: detail.ownership.owner, localize: CLILocalized.text)
        )
      )
    }
    // The output lists above hold only what macOS leaves undone, so say why.
    if detail.capabilities.outputOwner == ControllerServer.system.rawValue {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelOutputOwner"),
          CLILocalized.text("platform.macos.cli.controller.show.outputOwnerMacos")
        )
      )
    }
    if let tuning = detail.tuning {
      rows.append(
        (CLILocalized.text("cli.controller.show.labelTuning"), tuning.rows.joined(separator: ", "))
      )
    }
    if let virtual = detail.virtual {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelVirtual"),
          virtual.profile.map { profile in
            let source = virtual.source.map { CommandLineName.kebab($0.rawValue) } ?? ""
            return "\(CommandLineName.kebab(profile)) (\(source))"
          } ?? none
        )
      )
    }
    if let publication = detail.publication {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelPublication"),
          CommandLineName.kebab(publication.state)
            + (publication.reason.map { " (\(CommandLineName.kebab($0)))" }
              ?? publication.failure.map { " (\($0))" } ?? "")
        )
      )
    }
    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
    guard !detail.outputChecks.isEmpty else { return }
    CLIOutput.stdout("")
    CLIOutput.stdout(CLILocalized.text("cli.controller.show.labelOutputChecks"))
    for check in detail.outputChecks {
      CLIOutput.stdout("  \(check.command)")
      CLIOutput.stdout("    \(check.expected)")
    }
  }
}
