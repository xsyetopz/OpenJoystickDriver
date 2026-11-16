public import ArgumentParser
import Foundation
public import OpenJoystickDriverKit

/// The `ojd virtual` command group: shows, sets, resets and feeds the virtual gamepad personas, and
/// exports their mappings or launches a program with them.
struct VirtualCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "virtual",
    abstract: CLILocalized.text(
      "cli.virtual.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.virtual.group.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.virtual.group.discussionUnit"
      ),
    subcommands: [
      VirtualShowCommand.self, VirtualSetCommand.self, VirtualResetCommand.self,
      VirtualFeedCommand.self,
      VirtualExportMappingCommand.self, VirtualLaunchCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

extension VirtualHIDProfileID: ExpressibleByArgument {
  /// A persona on the command line is its lowercase kebab-case name, such as `sdl-compatible`.
  public init?(argument: String) {
    guard let persona = Self.allCases.first(where: { $0.commandLineName == argument }) else {
      return nil
    }
    self = persona
  }

  /// The persona names that the command line accepts.
  public static var allValueStrings: [String] { allCases.map(\.commandLineName) }
}

/// The `ojd virtual show --json` result.
struct VirtualShowReport: Encodable, Equatable {
  /// A connected controller and its virtual gamepad persona.
  struct Controller: Encodable, Equatable {
    /// The session token of the controller.
    let id: String
    /// The controller name.
    let name: String
    /// The USB vendor ID.
    let vendorID: Int
    /// The USB product ID.
    let productID: Int
    /// The persona the controller serves; absent when it serves none.
    let profile: String?
    /// Where the serving persona comes from.
    let source: VirtualHIDProfileSource?
    /// The persona that an override selects, when there is one.
    let override: String?
    /// How far the override reaches.
    let overrideScope: VirtualHIDProfileOverrideScope?
    /// True when virtual output is off because no persona is available for the controller.
    let unavailable: Bool
    /// The SDL mapping and W3C description of the live persona; absent with no persona.
    let sdl: VirtualSDLReport?
    /// The W3C description of the live persona; absent with no persona.
    let w3c: VirtualW3CReport?

    /// Creates the entry from the service's description of `device`.
    ///
    /// - Throws: the error of ``VirtualHIDProfileID/gamepadMapping()`` when the persona has no
    ///   mapping.
    init(_ device: ApplicationServiceDeviceDescription) throws {
      id = device.sessionToken.rawValue
      name = device.name
      vendorID = Int(device.vendorID)
      productID = Int(device.productID)
      let decision = device.servingDecision
      profile = decision.selection?.profileID.rawValue
      source = decision.selection?.source.reported
      override = device.virtualHIDProfile?.override?.rawValue
      overrideScope = device.virtualHIDProfile?.overrideScope
      unavailable = decision.route == .outputDisabled(.noVirtualProfile)
      let mapping = try decision.selection?.profileID.gamepadMapping()
      sdl = mapping.map(VirtualSDLReport.init)
      w3c = mapping.map(VirtualW3CReport.init)
    }
  }

  /// The connected controllers, or the one that the command selected.
  let controllers: [Controller]
  /// The names of every persona.
  let profiles: [String]
}

/// The `ojd virtual set` and `ojd virtual reset CONTROLLER` `--json` result.
struct VirtualChangeReport: Encodable, Equatable {
  /// The session token of the controller.
  let controller: String
  /// The persona that the command asked for; absent after a reset.
  let requested: String?
  /// The persona that serves the controller; absent when none does.
  let live: String?
  /// Where the live persona comes from.
  let source: VirtualHIDProfileSource
}

/// The `ojd virtual show` command: prints the persona of each connected controller, or of the one
/// selected.
struct VirtualShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.virtual.show.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to show; every connected controller when omitted.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let devices = try await ServiceConnection.request { client in
        let devices = try await client.getStatus().connectedDevices
        return try selector.map { [try $0.resolve(in: devices)] } ?? devices
      }
      let report = VirtualShowReport(
        controllers: try devices.map(VirtualShowReport.Controller.init),
        profiles: VirtualHIDProfileID.allCases.map(\.rawValue)
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain(
          report.controllers.map {
            [
              $0.id, $0.profile.map(CommandLineName.kebab) ?? "",
              $0.source.map { CommandLineName.kebab($0.rawValue) } ?? "",
              $0.override.map(CommandLineName.kebab) ?? "", $0.name,
            ]
          }
        )
      case .human: Self.printHuman(report)
      }
    }
  }

  /// Prints `report` as one line per controller, then the persona names.
  private static func printHuman(_ report: VirtualShowReport) {
    if report.controllers.isEmpty {
      CLIOutput.stderr(
        CLILocalized.text("cli.controller.list.empty")
      )
    }
    let idWidth = report.controllers.map(\.id.count).max() ?? 0
    for entry in report.controllers {
      let id = entry.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
      let profile: String
      if entry.unavailable {
        profile = CLILocalized.text("cli.virtual.show.unavailable")
      } else if let live = entry.profile {
        profile =
          "\(CommandLineName.kebab(live)) "
          + "(\(entry.source.map { CommandLineName.kebab($0.rawValue) } ?? ""))"
      } else {
        profile = CLILocalized.text("cli.virtual.show.none")
      }
      CLIOutput.stdout("\(id)  \(entry.name)  \(profile)")
      if let live = entry.profile, entry.sdl?.worksWithDefaultSDLHints == false {
        CLIOutput.stdout("\(id)  \(sdlHintsNote(live))")
      }
    }
    CLIOutput.stdout(
      CLILocalized.format(
        "cli.virtual.show.profiles",
        report.profiles.map(CommandLineName.kebab).joined(separator: ", ")
      )
    )
  }
}

/// The `--unit` flag of `virtual set` and `virtual reset`.
private let unitFlagHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.virtual.group.unit"
  )
)

/// Throws when `unit` is set and `device` has no unit ID, which the service would refuse.
private func requireUnit(_ unit: Bool, _ device: ApplicationServiceDeviceDescription) throws {
  guard unit, device.portKey == nil else { return }
  throw CLIFailure(
    .controllerRequestFailed,
    CLILocalized.format(
      "cli.virtual.group.errorNoUnit",
      device.name
    )
  )
}

/// Prints the outcome `result` of a persona change for `device`.
///
/// With virtual output off, the service stores the choice and applies it when output is on, which
/// is not a failure.
///
/// - Throws: ``CLIFailure`` with `serviceRequestFailed` when the service reports a failure.
private func printChange(
  _ result: VirtualHIDProfileOverrideResult,
  device: ApplicationServiceDeviceDescription
) throws {
  // With virtual output off, the service stores the choice and applies it when output is on.
  let stored = result.failure == .outputDisabled
  if let failure = result.failure, !stored {
    var reason = failure.code
    switch failure {
    case .activationFailed(let detail), .overrideFileKept(let detail): reason += ": " + detail
    default: break
    }
    throw CLIFailure(
      .serviceRequestFailed,
      CLILocalized.format(
        "cli.virtual.group.errorFailed",
        device.name,
        reason
      )
    )
  }
  let report = VirtualChangeReport(
    controller: device.sessionToken.rawValue,
    requested: result.requested?.rawValue,
    live: result.live?.rawValue,
    source: result.source
  )
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(report)
  case .plain:
    CLIOutput.plain([
      [
        report.controller, report.live.map(CommandLineName.kebab) ?? "",
        CommandLineName.kebab(report.source.rawValue),
      ]
    ])
  case .human where stored:
    CLIOutput.success(
      CLILocalized.format(
        "cli.virtual.group.stored",
        device.name
      )
    )
  case .human:
    CLIOutput.success(
      CLILocalized.format(
        "cli.virtual.group.changed",
        device.name,
        report.live.map(CommandLineName.kebab) ?? CLILocalized.text("cli.virtual.show.none"),
        CommandLineName.kebab(report.source.rawValue)
      )
    )
  }
}

/// The `ojd virtual set` command: selects the persona that a controller serves.
struct VirtualSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text(
      "cli.virtual.set.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The persona to serve.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.set.profile"),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID

  /// The controller to change.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--unit`: apply the choice to the controller's unit, not to this session alone.
  @Flag(help: unitFlagHelp)
  var unit = false

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let chosenProfile = profile
      let perUnit = unit
      let (device, result) = try await ServiceConnection.request(
        timeout: CLIContext.current.waitTimeout
      ) { client in
        let device = try await selector.resolve(with: client)
        try requireUnit(perUnit, device)
        let result = try await client.setVirtualHIDProfileOverride(
          chosenProfile.rawValue,
          for: .session(device.sessionToken),
          unit: perUnit
        )
        return (device, result)
      }
      try printChange(result, device: device)
    }
  }
}

/// The `ojd virtual reset` command: removes the persona override of one controller, or of every
/// controller with `--all`.
struct VirtualResetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "reset",
    abstract: CLILocalized.text(
      "cli.virtual.reset.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.virtual.reset.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to reset; omitted with `--all`.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  /// `-a`, `--all`: reset every controller.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.virtual.reset.all"))
  )
  var all = false

  /// `--unit`: apply the reset to the controller's unit, not to this session alone.
  @Flag(help: unitFlagHelp)
  var unit = false

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// `-n`, `--dry-run`: print what would change and change nothing.
  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.dryRun")
    )
  )
  var dryRun = false

  /// Rejects `--all` together with a controller or without one, and `--all` together with `--unit`.
  ///
  /// - Throws: ``ValidationError`` for those combinations.
  func validate() throws {
    guard all != (controller != nil) else {
      throw ValidationError(
        CLILocalized.text("cli.virtual.reset.errorTarget")
      )
    }
    guard !(all && unit) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.virtual.reset.errorUnitAll"
        )
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if all { try await resetAll() } else if let controller { try await reset(controller) }
    }
  }

  /// Resets the override of the controller that `selector` selects.
  ///
  /// `--dry-run` resolves the controller and prints what would change.
  private func reset(_ selector: ControllerSelector) async throws {
    if dryRun {
      let device = try await ServiceConnection.request { try await selector.resolve(with: $0) }
      try requireUnit(unit, device)
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.virtual.reset.dryRun",
          device.name
        )
      )
      return
    }
    let perUnit = unit
    let (device, result) = try await ServiceConnection.request(
      timeout: CLIContext.current.waitTimeout
    ) { client in
      let device = try await selector.resolve(with: client)
      try requireUnit(perUnit, device)
      let result = try await client.resetVirtualHIDProfileOverride(
        for: .session(device.sessionToken),
        unit: perUnit
      )
      return (device, result)
    }
    try printChange(result, device: device)
  }

  /// Resets everything that `--all` names through the service, after a confirmation that `--force`
  /// skips; `--dry-run` only prints the summary.
  ///
  /// - Throws: ``CLIFailure`` with `serviceRequestFailed` when the service does not reset.
  private func resetAll() async throws {
    let summary = CLILocalized.text(
      "cli.virtual.reset.allSummary"
    )
    if dryRun {
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.virtual.reset.allDryRun"
        )
      )
      return
    }
    try CLITerminal.confirm(summary, force: force)
    let reset = try await ServiceConnection.request(timeout: CLIContext.current.waitTimeout) {
      try await $0.resetSettings()
    }
    guard reset else {
      throw CLIFailure(
        .serviceRequestFailed,
        CLILocalized.text(
          "cli.virtual.reset.allFailed"
        )
      )
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(CLIStatus(details: ["reset": "All"]), kind: "Status")
    case .plain: CLIOutput.plain([["reset", "all"]])
    case .human:
      CLIOutput.success(
        CLILocalized.text(
          "cli.virtual.reset.allDone"
        )
      )
    }
  }
}
