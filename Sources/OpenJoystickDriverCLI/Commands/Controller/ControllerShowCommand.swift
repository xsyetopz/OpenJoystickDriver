import ArgumentParser
import Foundation
import OpenJoystickDriverKit

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
      let status = try await ServiceConnection.request { try await $0.getStatus() }
      let devices = status.connectedDevices
      if case .model(let model) = selector.reference,
        selector.reference.matches(in: devices).isEmpty,
        let unserved = status.unboundDevices.first(where: {
          $0.vendorID == model.vendorID && $0.productID == model.productID
        })
      {
        try UnservedControllerReport(unserved).print()
        return
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
    ]
    rows += detail.ownership.holders.map {
      ["holder", $0.processID.map { "\($0)" } ?? "", $0.name]
    }
    rows += [
      ["holds-exclusively", "\(detail.ownership.holdsExclusively)"],
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

  /// One labelled row of `controller show`.
  private typealias ShowRow = (label: String, value: String)

  /// The text for a list that may be empty.
  private static func showList(_ values: [String]) -> String {
    values.isEmpty ? CLILocalized.text("cli.controller.show.none") : values.joined(separator: ", ")
  }

  /// A kebab-case state followed by its kebab-case reason in parentheses, when there is one.
  private static func stateWithReason(_ state: String, reason: String?) -> String {
    CommandLineName.kebab(state) + (reason.map { " (\(CommandLineName.kebab($0)))" } ?? "")
  }

  /// The rows that name the controller and its link: name through session.
  private static func identityRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    [
      (CLILocalized.text("cli.controller.show.labelName"), detail.name),
      (CLILocalized.text("cli.controller.show.labelId"), detail.id),
      (
        CLILocalized.text("cli.controller.show.labelUnit"),
        detail.unit ?? CLILocalized.text("cli.controller.show.none")
      ),
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
  }

  /// The battery row and the Wii remote rows, for the hardware that reports them.
  private static func hardwareRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    var rows: [ShowRow] = []
    if let power = detail.power {
      let charging =
        power.charging == .unknown ? "" : " (\(CommandLineName.kebab(power.charging.rawValue)))"
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelBattery"),
          (power.battery.percentageText ?? CLILocalized.text("cli.controller.show.none")) + charging
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
    return rows
  }

  /// The input health row, absent while another client holds the controller.
  private static func inputHealthRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    // A controller that another client holds runs no input session, so it has no input health.
    guard detail.ownership.hidInput != HIDInputOwnership.ownedByAnotherClient.rawValue else {
      return []
    }
    return [
      (
        CLILocalized.text("cli.controller.show.labelInput"),
        stateWithReason(detail.inputHealth.state, reason: detail.inputHealth.failureReason)
      )
    ]
  }

  /// The ownership, server, serving, persona, and record rows, plus the macOS serving note.
  private static func servingRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    var rows: [ShowRow] = [
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
        stateWithReason(detail.serving.route, reason: detail.serving.reason)
      ),
      (
        CLILocalized.text("cli.controller.show.labelPersona"),
        detail.serving.persona.map(CommandLineName.kebab)
          ?? CLILocalized.text("cli.controller.show.none")
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
    return rows
  }

  /// The input mapping row and the unmapped-controls row.
  private static func inputMappingRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    guard let mapping = detail.inputMapping else { return [] }
    var rows: [ShowRow] = [
      (
        CLILocalized.text("cli.controller.show.labelInputMapping"),
        mapping.rowText(localize: CLILocalized.text)
      )
    ]
    if !mapping.unmapped.isEmpty {
      rows.append(
        (
          CLILocalized.text("cli.controller.show.labelUnmapped"),
          mapping.unmapped.joined(separator: ", ")
        )
      )
    }
    return rows
  }

  /// The controls, rumble, and lighting rows.
  private static func capabilityRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    [
      (
        CLILocalized.text("cli.controller.show.labelControls"),
        showList(detail.capabilities.controls.map(CommandLineName.kebab))
      ),
      (
        CLILocalized.text("cli.controller.show.labelRumble"),
        showList(detail.capabilities.rumbleMotors.map(CommandLineName.kebab))
      ),
      (
        CLILocalized.text("cli.controller.show.labelLighting"),
        showList(detail.capabilities.lightingFeatures.map(CommandLineName.kebab))
      ),
    ]
  }

  /// The exclusive owner, holders, and next-step rows.
  private static func holderRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    var rows: [ShowRow] = []
    if detail.ownership.hidInput == HIDInputOwnership.ownedByAnotherClient.rawValue {
      rows.append(
        (
          CLILocalized.text("ui.controllers.exclusiveOwner"),
          USBExclusiveOwner.heldMessage(for: detail.ownership.owner, localize: CLILocalized.text)
        )
      )
    }
    rows.append(
      (
        CLILocalized.text("ui.controllers.holders"),
        showList(detail.ownership.holders.map { $0.label(localize: CLILocalized.text) })
      )
    )
    let nextStep = CLILocalized.text("cli.controller.show.labelNextStep")
    if detail.ownership.holdsExclusively {
      rows += [
        (
          CLILocalized.text("ui.controllers.exclusiveOwner"),
          CLILocalized.text("status.controllerExclusive")
        ),
        (nextStep, CLILocalized.format("cli.controller.show.suspendHint", detail.id)),
      ]
    } else if detail.session == ControllerSessionState.suspended.rawValue {
      rows.append((nextStep, CLILocalized.format("cli.controller.show.resumeHint", detail.id)))
    }
    return rows
  }

  /// The output owner, tuning, virtual device, and publication rows.
  private static func deviceStateRows(_ detail: ControllerShowReport.Detail) -> [ShowRow] {
    var rows: [ShowRow] = []
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
    rows += virtualRows(detail.virtual)
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
    return rows
  }

  /// The virtual device row and its no-game-rumble note.
  private static func virtualRows(_ virtual: ControllerShowReport.Virtual?) -> [ShowRow] {
    guard let virtual else { return [] }
    var rows: [ShowRow] = [
      (
        CLILocalized.text("cli.controller.show.labelVirtual"),
        virtual.profile.map { profile in
          let source = virtual.source.map { CommandLineName.kebab($0.rawValue) } ?? ""
          return "\(CommandLineName.kebab(profile)) (\(source))"
        } ?? CLILocalized.text("cli.controller.show.none")
      )
    ]
    if virtual.gameRumbleUnavailable,
      let profile = virtual.profile.flatMap({ VirtualHIDProfileID(rawValue: $0) })
    {
      rows.append(("", noGameRumbleNote(profile)))
    }
    return rows
  }

  /// Prints the labelled rows of `controller show` for people.
  private static func printHuman(_ detail: ControllerShowReport.Detail) {
    let rows =
      identityRows(detail) + hardwareRows(detail) + inputHealthRows(detail)
      + servingRows(detail) + inputMappingRows(detail) + capabilityRows(detail)
      + holderRows(detail) + deviceStateRows(detail)
    let width = rows.map(\.label.count).max() ?? 0
    for (label, value) in rows {
      CLIOutput.stdout(label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
    printOutputChecks(detail.outputChecks)
  }

  /// Prints the expected output of each output check under its own heading.
  private static func printOutputChecks(_ checks: [ControllerShowReport.OutputCheck]) {
    guard !checks.isEmpty else { return }
    CLIOutput.stdout("")
    CLIOutput.stdout(CLILocalized.text("cli.controller.show.labelOutputChecks"))
    for check in checks {
      CLIOutput.stdout("  \(check.command)")
      CLIOutput.stdout("    \(check.expected)")
    }
  }
}
