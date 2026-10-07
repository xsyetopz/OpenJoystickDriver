import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct PermissionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "permission",
    abstract: CLILocalized.text(
      "cli.permission.abstract"
    ),
    subcommands: [PermissionListCommand.self, PermissionRequestCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Prints `report`; as a list of `items` for `ojd permission list --json`.
  static func print(_ report: PermissionReport, asList: Bool = false) throws {
    switch CLIContext.current.format {
    case .json where asList: try CLIOutput.json(CLIList(items: report.permissions))
    case .json: try CLIOutput.json(report)
    case .plain: CLIOutput.plain(report.plainRows)
    case .human:
      let rows = PermissionID.allCases.map {
        ($0.localizedName, report.state(of: $0).rawValue, $0.localizedPurpose)
      }
      let nameWidth = rows.map(\.0.count).max() ?? 0
      let stateWidth = rows.map(\.1.count).max() ?? 0
      for (name, state, purpose) in rows {
        CLIOutput.stdout(
          name.padding(toLength: nameWidth, withPad: " ", startingAt: 0) + "  "
            + state.padding(toLength: stateWidth, withPad: " ", startingAt: 0) + "  " + purpose
        )
      }
    }
  }
}

struct PermissionListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.permission.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.permission.list.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let snapshot: PermissionManager.Snapshot
      do {
        let payload = try await ServiceConnection.request { try await $0.getStatus() }
        snapshot = PermissionManager.Snapshot(
          inputMonitoring: PermissionManager.AccessState(status: payload.inputMonitoring),
          accessibility: PermissionManager.AccessState(status: payload.accessibility)
        )
      } catch let failure as CLIFailure where failure.code == .serviceUnavailable {
        snapshot = Self.localSnapshot()
        CLIOutput.stderr(
          CLILocalized.text(
            "cli.permission.list.local_state"
          )
        )
      }
      try PermissionCommand.print(
        PermissionReport(snapshot: snapshot, extensionStatus: StatusCommand.extensionProbe()),
        asList: true
      )
    }
  }

  /// Reads the permissions in this process, as the service would if it were running.
  @TaskLocal
  static var localSnapshot: @Sendable () -> PermissionManager.Snapshot = {
    PermissionManager.Snapshot(
      inputMonitoring: PermissionManager.currentInputMonitoringAccessState(),
      accessibility: PermissionManager.currentAccessibilityAccessState()
    )
  }
}

struct PermissionRequestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "request",
    abstract: CLILocalized.text(
      "cli.permission.request.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.permission.request.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.permission.request.ids"
      ),
      valueName: "id"
    )
  )
  var ids: [String] = []

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func validate() throws {
    let valid = PermissionID.requestable.map(\.rawValue)
    for id in ids where !valid.contains(id) {
      throw ValidationError(
        CLILocalized.format(
          "cli.permission.request.unknown_id",
          id,
          valid.joined(separator: ", ")
        )
      )
    }
  }

  func run() async throws {
    try await global.run {
      let requested = ids.compactMap(PermissionID.init)
      let targets = requested.isEmpty ? PermissionID.requestable : requested
      let snapshot = try await ServiceConnection.request(
        timeout: CLIContext.current.timeout ?? ServiceTimeouts.permissionRequest
      ) { client in
        guard let first = requested.first else { return try await client.requestRequiredAccess() }
        var latest = try await client.requestAccess(first.accessRequirement)
        for permission in requested.dropFirst() {
          latest = try await client.requestAccess(permission.accessRequirement)
        }
        return latest
      }
      let report = PermissionReport(
        snapshot: snapshot,
        extensionStatus: StatusCommand.extensionProbe()
      )
      try PermissionCommand.print(report)
      let missing = targets.filter { report.state(of: $0) != .granted }
      guard missing.isEmpty else { throw CLIFailure.permissionStillMissing(missing) }
      CLIOutput.success(
        CLILocalized.text("cli.permission.request.granted")
      )
    }
  }
}

extension PermissionID {
  var accessRequirement: PermissionManager.Requirement {
    self == .accessibility ? .accessibility : .inputMonitoring
  }
}

extension CLIFailure {
  /// A requested permission is still not granted; `missing` holds at least one id.
  static func permissionStillMissing(_ missing: [PermissionID]) -> Self {
    Self(
      .permissionMissing,
      CLILocalized.format(
        "cli.error.permission_still_missing",
        missing.map(\.localizedName).joined(separator: ", "),
        missing.map(\.localizedSettingsPane).joined(separator: " and ")
      )
    )
  }
}
