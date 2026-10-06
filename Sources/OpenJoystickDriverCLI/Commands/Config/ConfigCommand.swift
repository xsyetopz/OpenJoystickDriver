import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ConfigCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: CLILocalized.text("cli.config.abstract"),
    discussion: CLILocalized.text("cli.config.discussion"),
    subcommands: [ConfigShowCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

struct ConfigShowCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.config.show.abstract"),
    discussion: CLILocalized.text("cli.config.show.discussion")
  )

  /// One tuning value and the layer that set it. `value` is nil while only the driver default
  /// applies, which the driver picks itself.
  struct Value: Encodable, Equatable {
    let key: String
    let value: Double?
    let layer: String
  }

  /// The `--json` result. `controller` is absent without `--controller`.
  struct Result: Encodable, Equatable {
    let controller: String?
    let profile: String?
    let defaultsFile: String
    let defaultsProblem: String?
    let values: [Value]
  }

  @Option(
    name: .customLong("controller"),
    help: ArgumentHelp(CLILocalized.text("cli.config.show.controller"), valueName: "VVVV:PPPP")
  )
  var controller: RecordIdentity?

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let result = try Self.result(
        for: controller,
        in: RecordStore.load(),
        activeProfile: await Self.activeProfile(for: controller)
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain(result.values.map { [$0.key, Self.text($0.value), $0.layer] })
      case .human:
        if let problem = result.defaultsProblem {
          CLIOutput.stderr(
            CLILocalized.format("cli.config.show.defaults_ignored", result.defaultsFile, problem)
          )
        }
        let width = result.values.map(\.key.count).max() ?? 0
        for item in result.values {
          let key = item.key.padding(toLength: width, withPad: " ", startingAt: 0)
          CLIOutput.stdout("\(key)  \(Self.text(item.value))  (\(item.layer))")
        }
      }
    }
  }

  /// The profile that is active for `identity`, or nil without `--controller`, without a running
  /// service, or without an active profile for that model. The service is optional here, so
  /// `config show` keeps working offline and then shows no profile rows.
  private static func activeProfile(for identity: RecordIdentity?) async -> RemappingProfile? {
    guard let identity,
      let snapshot = try? await ServiceConnection.request({ try await $0.getRemappingSnapshot() }),
      let active = snapshot.activeProfiles.routingActiveProfile(
        vendorID: identity.identity.vendorID,
        productID: identity.identity.productID
      )
    else { return nil }
    return snapshot.profiles.first { $0.id == active.profileID }
  }

  /// Each tuning key with its effective value and layer: the controller's record when one is
  /// named, else the global defaults over the driver defaults. The active profile adds one
  /// `profile` row for each stick mapping's `innerDeadzone`, keyed as `profile get` names it.
  /// The profile value calibrates that mapping's output and does not override `stickDeadzone`.
  static func result(
    for identity: RecordIdentity?,
    in set: ControllerRecordSet,
    activeProfile: RemappingProfile? = nil
  ) throws -> Result {
    let defaults = set.defaults
    var tuning = defaults?.tuning ?? .none
    var layers: [String: ControllerRecordLayer] = [:]
    for key in tuning.setKeys { layers[key.rawValue] = .global }
    if let identity {
      guard let record = set.records[identity.identity] else {
        throw CLIFailure(.notFound, CLILocalized.format("cli.record.show.not_found", identity.text))
      }
      tuning = record.tuning
      layers = record.tuningLayers
    }
    let values = ControllerTuning.Key.allCases.map { key in
      Value(
        key: key.rawValue,
        value: tuning.text(of: key).flatMap(Double.init),
        layer: (layers[key.rawValue] ?? .driver).rawValue
      )
    }
    let profileValues = (activeProfile?.stickMappings ?? []).enumerated().map { index, mapping in
      Value(
        key: "stickMappings.\(index).tuning.innerDeadzone",
        value: mapping.tuning.innerDeadzone,
        layer: "profile"
      )
    }
    return Result(
      controller: identity?.text,
      profile: activeProfile?.name,
      defaultsFile: (defaults?.url ?? ControllerDefaults.userFile).path,
      defaultsProblem: defaults?.problem,
      values: values + profileValues
    )
  }

  private static func text(_ value: Double?) -> String {
    value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
      ?? CLILocalized.text("cli.config.show.unset")
  }
}
