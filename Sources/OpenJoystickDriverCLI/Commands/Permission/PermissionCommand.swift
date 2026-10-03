import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

struct PermissionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "permission",
    abstract: CLILocalized.text(
      "cli.permission.abstract",
      "Show or request the macOS permissions OpenJoystickDriver needs."
    ),
    subcommands: [PermissionListCommand.self, PermissionRequestCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions

  static func print(_ report: PermissionReport) throws {
    switch CLIContext.current.format {
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
      "cli.permission.list.abstract",
      "List each permission, its state, and what OpenJoystickDriver uses it for."
    ),
    discussion: CLILocalized.text(
      "cli.permission.list.discussion",
      "States are granted, denied, or unknown. When the service is stopped, the state is "
        + "read in this process and a note on stderr says so; exit code stays 0."
    )
  )

  @OptionGroup
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
            "cli.permission.list.local_state",
            "The service is not running, so these states were read by this process. "
              + "Start the service with 'ojd service start' for the state it sees."
          )
        )
      }
      try PermissionCommand.print(
        PermissionReport(snapshot: snapshot, extensionStatus: StatusCommand.extensionProbe())
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
      "cli.permission.request.abstract",
      "Ask the service to request permissions; it never prompts in the terminal."
    ),
    discussion: CLILocalized.text(
      "cli.permission.request.discussion",
      "macOS shows its own prompt for the service. Exits 77 when a requested permission is "
        + "still not granted. Without ids, requests input-monitoring and accessibility."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.permission.request.ids",
        "Permissions to request: input-monitoring or accessibility."
      ),
      valueName: "id"
    )
  )
  var ids: [String] = []

  @OptionGroup
  var global: GlobalOptions

  func validate() throws {
    let valid = PermissionID.requestable.map(\.rawValue)
    for id in ids where !valid.contains(id) {
      throw ValidationError(
        CLILocalized.format(
          "cli.permission.request.unknown_id",
          "Unknown permission '%@'. Use %@.",
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
        timeout: CLIContext.current.timeout ?? Self.defaultRequestTimeout
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
        CLILocalized.text("cli.permission.request.granted", "The requested access is granted.")
      )
    }
  }

  /// Seconds the service may take, since it waits for macOS to register the request.
  static let defaultRequestTimeout: Double = 10
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
      .permissionDenied,
      CLILocalized.format(
        "cli.error.permission_still_missing",
        "%@ access is still missing. Allow OpenJoystickDriver in System Settings > %@, "
          + "then run 'ojd permission request' again.",
        missing.map(\.localizedName).joined(separator: ", "),
        missing.map(\.localizedSettingsPane).joined(separator: " and ")
      )
    )
  }
}
