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
  /// applies, which the driver picks itself. `families` lists the protocol families that read the
  /// key; it is set for a tuning key only without `--controller`.
  struct Value: Encodable, Equatable {
    let key: String
    let value: Double?
    let layer: String
    let families: [String]?
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
      let set = RecordStore.load()
      let result = try Self.result(
        for: controller,
        in: set,
        activeProfile: await Self.activeProfile(for: controller)
      )
      if controller == nil {
        switch await Self.unreadDefaults(in: set) {
        case .ran(let keys):
          for key in keys {
            CLIOutput.stderr(
              CLILocalized.format(
                "cli.config.show.unread",
                key.rawValue,
                Self.families(reading: key, in: set).joined(separator: ", ")
              )
            )
          }
        case .skipped(let serviceRunning):
          CLIOutput.stderr(
            CLILocalized.text(
              serviceRunning
                ? "cli.config.show.unread_skipped_no_controller"
                : "cli.config.show.unread_skipped_no_service"
            )
          )
        }
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain(
          result.values.map {
            [$0.key, Self.text($0.value), $0.layer]
              + [$0.families?.joined(separator: ",")].compactMap { $0 }
          }
        )
      case .human:
        if let problem = result.defaultsProblem {
          CLIOutput.stderr(
            CLILocalized.format("cli.config.show.defaults_ignored", result.defaultsFile, problem)
          )
        }
        let width = result.values.map(\.key.count).max() ?? 0
        for item in result.values {
          let key = item.key.padding(toLength: width, withPad: " ", startingAt: 0)
          let families = item.families.map {
            "  " + CLILocalized.format("cli.config.show.read_by", $0.joined(separator: ", "))
          }
          CLIOutput.stdout("\(key)  \(Self.text(item.value))  (\(item.layer))\(families ?? "")")
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

  /// The protocol families with a record whose driver reads `key`, sorted.
  static func families(reading key: ControllerTuning.Key, in set: ControllerRecordSet) -> [String] {
    Set(set.records.values.filter { $0.reads(key) }.map(\.family)).sorted()
  }

  /// The outcome of checking the keys `Defaults.json` sets against the connected controllers.
  private enum UnreadCheck {
    /// The keys no connected controller reads, in key order.
    case ran([ControllerTuning.Key])
    /// The check could not name the connected controllers.
    case skipped(serviceRunning: Bool)
  }

  /// Checks the keys `Defaults.json` sets against the connected controllers. The service is asked
  /// only when some record ignores a key `Defaults.json` sets. Without a running service or a
  /// connected controller the check is skipped, so the caller can say so instead of looking clean.
  private static func unreadDefaults(in set: ControllerRecordSet) async -> UnreadCheck {
    let keys = ControllerTuning.Key.allCases.filter { key in
      set.defaults?.tuning.setKeys.contains(key) == true
        && set.records.values.contains { !$0.reads(key) }
    }
    guard !keys.isEmpty else { return .ran([]) }
    guard let status = try? await ServiceConnection.request({ try await $0.getStatus() }) else {
      return .skipped(serviceRunning: false)
    }
    guard !status.connectedDevices.isEmpty else { return .skipped(serviceRunning: true) }
    return .ran(unreadKeys(keys, in: set, connected: status.connectedDevices))
  }

  /// The members of `keys` that no record of a `connected` controller reads. A controller without
  /// a record reads none, because only a record carries a tuning.
  static func unreadKeys(
    _ keys: [ControllerTuning.Key],
    in set: ControllerRecordSet,
    connected: [ApplicationServiceDeviceDescription]
  ) -> [ControllerTuning.Key] {
    let records = connected.compactMap {
      set.records[ControllerIdentity(vendorID: $0.vendorID, productID: $0.productID)]
    }
    return keys.filter { key in !records.contains { $0.reads(key) } }
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
        layer: (layers[key.rawValue] ?? .driver).rawValue,
        families: identity == nil ? Self.families(reading: key, in: set) : nil
      )
    }
    let profileValues = (activeProfile?.stickMappings ?? []).enumerated().map { index, mapping in
      Value(
        key: "stickMappings.\(index).tuning.innerDeadzone",
        value: mapping.tuning.innerDeadzone,
        layer: "profile",
        families: nil
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
