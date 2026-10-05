import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct VirtualCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "virtual",
    abstract: CLILocalized.text(
      "cli.virtual.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.virtual.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.virtual.discussion.unit"
      ),
    subcommands: [
      VirtualShowCommand.self, VirtualSetCommand.self, VirtualResetCommand.self,
      VirtualFeedCommand.self,
    ]
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
    let overrideScope: String?
    let unavailable: Bool

    init(_ device: ApplicationServiceDeviceDescription) {
      id = device.runtimeIdentifier
      name = device.name
      vendorID = Int(device.vendorID)
      productID = Int(device.productID)
      profile = device.virtualHIDProfile?.profile?.rawValue
      source = device.virtualHIDProfile?.source
      override = device.virtualHIDProfile?.override?.rawValue
      overrideScope = device.virtualHIDProfile?.overrideScope
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
      "cli.virtual.show.abstract"
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
        CLILocalized.text("cli.controller.list.empty")
      )
    }
    let idWidth = report.controllers.map(\.id.count).max() ?? 0
    for controller in report.controllers {
      let id = controller.id.padding(toLength: idWidth, withPad: " ", startingAt: 0)
      let profile: String
      if controller.unavailable {
        profile = CLILocalized.text("cli.virtual.show.unavailable")
      } else if let live = controller.profile {
        profile = "\(live) (\(controller.source ?? ""))"
      } else {
        profile = CLILocalized.text("cli.virtual.show.none")
      }
      CLIOutput.stdout("\(id)  \(controller.name)  \(profile)")
    }
    CLIOutput.stdout(
      CLILocalized.format(
        "cli.virtual.show.profiles",
        report.profiles.joined(separator: ", ")
      )
    )
  }
}

/// The `--unit` flag of `virtual set` and `virtual reset`.
private let unitFlagHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.virtual.unit"
  )
)

/// Throws when `unit` is set and `device` has no unit ID, which the service would refuse.
private func requireUnit(_ unit: Bool, _ device: ApplicationServiceDeviceDescription) throws {
  guard unit, device.unitIdentifier == nil else { return }
  throw CLIFailure(
    .controllerRequestFailed,
    CLILocalized.format(
      "cli.virtual.error.no_unit",
      device.name
    )
  )
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
      .serviceRequestFailed,
      CLILocalized.format(
        "cli.virtual.error.failed",
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
        device.name
      )
    )
  case .human:
    CLIOutput.success(
      CLILocalized.format(
        "cli.virtual.changed",
        device.name,
        report.live ?? CLILocalized.text("cli.virtual.show.none"),
        report.source
      )
    )
  }
}

struct VirtualSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text(
      "cli.virtual.set.abstract"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.set.profile"),
      valueName: "profile"
    )
  )
  var profile: VirtualHIDProfileID

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Flag(help: unitFlagHelp)
  var unit = false

  func run() async throws {
    try await global.run {
      let selector = controller
      let profile = profile
      let unit = unit
      let (device, result) = try await ServiceConnection.request(
        timeout: CLIContext.current.waitTimeout
      ) { client in
        let device = try await selector.resolve(with: client)
        try requireUnit(unit, device)
        let result = try await client.setVirtualHIDProfileOverride(
          profile.rawValue,
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier,
          unit: unit
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
      "cli.virtual.reset.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.virtual.reset.discussion"
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.virtual.reset.all"))
  )
  var all = false

  @Flag(help: unitFlagHelp)
  var unit = false

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @Flag(
    name: [.customShort("n"), .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.dry_run")
    )
  )
  var dryRun = false

  func validate() throws {
    guard all != (controller != nil) else {
      throw ValidationError(
        CLILocalized.text("cli.virtual.reset.error.target")
      )
    }
    guard !(all && unit) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.virtual.reset.error.unit_all"
        )
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
      try requireUnit(unit, device)
      CLIOutput.stdout(
        CLILocalized.format(
          "cli.virtual.reset.dry_run",
          device.name
        )
      )
      return
    }
    let unit = unit
    let (device, result) = try await ServiceConnection.request(
      timeout: CLIContext.current.waitTimeout
    ) { client in
      let device = try await selector.resolve(with: client)
      try requireUnit(unit, device)
      let result = try await client.resetVirtualHIDProfileOverride(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier,
        unit: unit
      )
      return (device, result)
    }
    try printChange(result, device: device)
  }

  private func resetAll() async throws {
    let summary = CLILocalized.text(
      "cli.virtual.reset.all.summary"
    )
    if dryRun {
      CLIOutput.stdout(
        CLILocalized.text(
          "cli.virtual.reset.all.dry_run"
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
          "cli.virtual.reset.all.failed"
        )
      )
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(["reset": "all"])
    case .plain: CLIOutput.plain([["reset", "all"]])
    case .human:
      CLIOutput.success(
        CLILocalized.text(
          "cli.virtual.reset.all.done"
        )
      )
    }
  }
}
