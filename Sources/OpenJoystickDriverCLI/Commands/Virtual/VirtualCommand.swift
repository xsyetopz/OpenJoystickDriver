import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct VirtualCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "virtual",
    abstract: CLILocalized.text(
      "cli.virtual.abstract",
      "Show and choose the virtual gamepad OpenJoystickDriver publishes for a controller."
    ),
    discussion: CLILocalized.text(
      "cli.virtual.discussion",
      "A choice applies to every controller of the same model. 'reset' returns a model to "
        + "automatic selection."
    ),
    subcommands: [VirtualShowCommand.self, VirtualSetCommand.self, VirtualResetCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

extension VirtualHIDProfileID: ExpressibleByArgument {
  public init?(argument: String) { self.init(rawValue: argument) }
}

/// The `ojd virtual show --json` result.
struct VirtualShowReport: Encodable, Equatable {
  struct Controller: Encodable, Equatable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let profile: String?
    let source: String?
    let override: String?
    let unavailable: Bool

    init(_ device: ApplicationServiceDeviceDescription) {
      id = device.runtimeIdentifier
      name = device.name
      vendorID = Int(device.vendorID)
      productID = Int(device.productID)
      profile = device.virtualHIDProfile?.profile?.rawValue
      source = device.virtualHIDProfile?.source
      override = device.virtualHIDProfile?.override?.rawValue
      unavailable = device.virtualHIDProfile?.unavailable ?? false
    }
  }

  let controllers: [Controller]
  let profiles: [String]
}

/// The `ojd virtual set` and `ojd virtual reset CONTROLLER` `--json` result.
struct VirtualChangeReport: Encodable, Equatable {
  let controller: String
  let requested: String?
  let live: String?
  let source: String
}

struct VirtualShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text(
      "cli.virtual.show.abstract",
      "Show each controller's virtual gamepad and the profiles you can choose."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  func run() async throws {
    try await global.run {
      let selector = controller
      let devices = try await ServiceConnection.request { client in
        let devices = try await client.getStatus().connectedDevices
        return try selector.map { [try $0.resolve(in: devices)] } ?? devices
      }
      let report = VirtualShowReport(
        controllers: devices.map(VirtualShowReport.Controller.init),
        profiles: VirtualHIDProfileID.allCases.map(\.rawValue)
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(report)
      case .plain:
        CLIOutput.plain(
          report.controllers.map {
            [$0.id, $0.profile ?? "", $0.source ?? "", $0.override ?? "", $0.name]
          }
        )
      case .human: Self.printHuman(report)
      }
    }
  }

  private static func printHuman(_ report: VirtualShowReport) {
    if report.controllers.isEmpty {
      CLIOutput.stderr(
        CLILocalized.text("cli.controller.list.empty", "No controllers are connected.")
      )
    }
    let idWidth = report.controllers.map(\.id.count).max() ?? 0
    for controller in report.controllers {
      let id = controller.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
      let profile: String
      if controller.unavailable {
        profile = CLILocalized.text("cli.virtual.show.unavailable", "no virtual gamepad fits")
      } else if let live = controller.profile {
        profile = "\(live) (\(controller.source ?? ""))"
      } else {
        profile = CLILocalized.text("cli.virtual.show.none", "no virtual gamepad")
      }
      CLIOutput.stdout("\(id)  \(controller.name)  \(profile)")
    }
    CLIOutput.stdout(
      CLILocalized.format(
        "cli.virtual.show.profiles",
        "Profiles: %@",
        report.profiles.joined(separator: ", ")
      )
    )
  }
}

private func printChange(
  _ result: VirtualHIDProfileOverrideResult,
  device: ApplicationServiceDeviceDescription
) throws {
  // With virtual output off, the service stores the choice and applies it when output is on.
  let stored = result.failure == .outputDisabled
  if let failure = result.failure, !stored {
    var reason = failure.code
    if case .activationFailed(let detail) = failure { reason += ": " + detail }
    throw CLIFailure(
      .failure,
      CLILocalized.format(
        "cli.virtual.error.failed",
        "The virtual gamepad for %@ did not change (%@). Check it with 'ojd virtual show'.",
        device.name,
        reason
      )
    )
  }
  let report = VirtualChangeReport(
    controller: device.runtimeIdentifier,
    requested: result.requested?.rawValue,
    live: result.live?.rawValue,
    source: result.source
  )
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(report)
  case .plain: CLIOutput.plain([[report.controller, report.live ?? "", report.source]])
  case .human where stored:
    CLIOutput.success(
      CLILocalized.format(
        "cli.virtual.stored",
        "Saved the choice for %@. It applies once virtual output is enabled.",
        device.name
      )
    )
  case .human:
    CLIOutput.success(
      CLILocalized.format(
        "cli.virtual.changed",
        "%@ now publishes %@ (%@).",
        device.name,
        report.live ?? CLILocalized.text("cli.virtual.show.none", "no virtual gamepad"),
        report.source
      )
    )
  }
}

struct VirtualSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text(
      "cli.virtual.set.abstract",
      "Choose the virtual gamepad for a controller's model."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.set.profile", "The virtual gamepad profile."),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  func run() async throws {
    try await global.run {
      let selector = controller
      let profile = profile
      let (device, result) = try await ServiceConnection.request(
        timeout: CLIContext.current.waitTimeout
      ) { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.setVirtualHIDProfileOverride(
          profile.rawValue,
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
        return (device, result)
      }
      try printChange(result, device: device)
    }
  }
}

struct VirtualResetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reset",
    abstract: CLILocalized.text(
      "cli.virtual.reset.abstract",
      "Return a controller's model, or every model, to automatic virtual gamepad selection."
    ),
    discussion: CLILocalized.text(
      "cli.virtual.reset.discussion",
      "--all also clears choices for models that are not connected. It asks first on a "
        + "terminal and needs --force otherwise."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.virtual.reset.all", "Reset every controller model."))
  )
  var all = false

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run", "Print what would change, and change nothing.")
    )
  )
  var dryRun = false

  func validate() throws {
    guard all != (controller != nil) else {
      throw ValidationError(
        CLILocalized.text("cli.virtual.reset.error.target", "Give either a CONTROLLER or --all.")
      )
    }
  }

  func run() async throws {
    try await global.run {
      if all { try await resetAll() } else if let controller { try await reset(controller) }
    }
  }

  private func reset(_ selector: ControllerSelector) async throws {
    if dryRun {
      let device = try await ServiceConnection.request { try await selector.resolve(with: $0) }
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.virtual.reset.dry_run",
          "Would return %@ to automatic virtual gamepad selection.",
          device.name
        )
      )
      return
    }
    let (device, result) = try await ServiceConnection.request(
      timeout: CLIContext.current.waitTimeout
    ) { client in
      let device = try await selector.resolve(with: client)
      let result = try await client.resetVirtualHIDProfileOverride(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      return (device, result)
    }
    try printChange(result, device: device)
  }

  private func resetAll() async throws {
    let summary = CLILocalized.text(
      "cli.virtual.reset.all.summary",
      "Return every controller model to automatic virtual gamepad selection?"
    )
    if dryRun {
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.virtual.reset.all.dry_run",
          "Would return every controller model to automatic virtual gamepad selection."
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
        .failure,
        CLILocalized.text(
          "cli.virtual.reset.all.failed",
          "The service could not clear the virtual gamepad choices. Check it with 'ojd status'."
        )
      )
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(["reset": "all"])
    case .plain: CLIOutput.plain([["reset", "all"]])
    case .human:
      CLIOutput.success(
        CLILocalized.text(
          "cli.virtual.reset.all.done",
          "Every controller model now selects its virtual gamepad automatically."
        )
      )
    }
  }
}
