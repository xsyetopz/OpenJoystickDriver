import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd permission` command group: list the macOS permissions OJD needs, or ask the service to
/// request them.
struct PermissionCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "permission",
    abstract: CLILocalized.text(
      "platform.macos.cli.permission.group.abstract"
    ),
    subcommands: [PermissionListCommand.self, PermissionRequestCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Prints `report`; as a list of `items` for `ojd permission list --json`.
  static func print(_ report: PermissionReport, asList: Bool = false) throws {
    switch CLIContext.current.format {
    case .json where asList: try CLIOutput.json(CLIList(items: report.permissions))
    case .json: try CLIOutput.json(report)
    case .plain: CLIOutput.plain(report.plainRows)
    case .human:
      let rows = report.permissions.compactMap { entry -> (String, String, String)? in
        guard let id = PermissionID(rawValue: entry.id) else { return nil }
        var purpose = id.localizedPurpose
        if entry.requiredByActiveProfile == true {
          purpose += " (" + CLILocalized.text("cli.permission.group.requiredByProfile") + ")"
        }
        return (id.localizedName, CommandLineName.kebab(entry.state.rawValue), purpose)
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

/// The `ojd permission list` command: prints each permission, its state and what OJD uses it for.
///
/// Without a running service it reads the permissions of its own process.
struct PermissionListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text(
      "cli.permission.list.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.permission.list.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let snapshot: PermissionManager.Snapshot
      let postEvent: PermissionReport.PostEvent
      do {
        let (payload, remapping) = try await ServiceConnection.request { client in
          (try await client.getStatus(), try await client.getRemappingSnapshot())
        }
        snapshot = PermissionManager.Snapshot(
          inputRead: payload.inputRead,
          inputInject: payload.inputInject
        )
        postEvent = PermissionReport.PostEvent(
          state: remapping.postEventAccess == .granted ? .granted : .denied,
          requiredByActiveProfile: remapping.requiresPostEventAccess
        )
      } catch let failure as CLIFailure where failure.code == .serviceUnavailable {
        snapshot = Self.localSnapshot()
        postEvent = PermissionReport.PostEvent(
          state: Self.localPostEventAccess() == .granted ? .granted : .denied,
          requiredByActiveProfile: nil
        )
        CLIOutput.stderr(
          CLILocalized.text(
            "cli.permission.list.localState"
          )
        )
      }
      try PermissionCommand.print(
        PermissionReport(
          snapshot: snapshot,
          extensionStatus: StatusCommand.extensionProbe(),
          postEvent: postEvent
        ),
        asList: true
      )
    }
  }

  /// Reads the permissions in this process, as the service would if it were running.
  @TaskLocal
  static var localSnapshot: @Sendable () -> PermissionManager.Snapshot = {
    PermissionManager.Snapshot(
      inputRead: PlatformHosts.current.accessControl.inputReadAccessState(),
      inputInject: PlatformHosts.current.accessControl.inputInjectAccessState()
    )
  }

  /// Reads the Post Event access of this process, as the service would if it were running.
  @TaskLocal
  static var localPostEventAccess: @Sendable () -> RemappingPostEventAccessState = {
    PlatformHosts.current.accessControl.postEventAccessState()
  }
}

/// The `ojd permission request` command: asks the service to request the named permissions.
///
/// macOS shows its own prompt; the command never prompts in the terminal. It fails with exit code
/// 77 when a permission is still not granted.
struct PermissionRequestCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "request",
    abstract: CLILocalized.text(
      "cli.permission.request.abstract"
    ),
    discussion: CLILocalized.text(
      "platform.macos.cli.permission.request.discussion"
    )
  )

  /// The permissions to request; both `input-read` and `input-inject` when none is named.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.permission.request.ids"
      ),
      valueName: "id"
    )
  )
  var ids: [String] = []

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that every ID is a permission that can be requested.
  ///
  /// - Throws: ``ValidationError`` that lists the valid IDs.
  func validate() throws {
    let valid = PermissionID.requestable.map(\.commandLineName)
    for id in ids where !valid.contains(id) {
      throw ValidationError(
        CLILocalized.format(
          "cli.permission.request.unknownId",
          id,
          valid.joined(separator: ", ")
        )
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let requested = ids.compactMap { CommandLineName.value(of: $0, in: PermissionID.self) }
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
  /// The permission as the requirement that the service requests.
  var accessRequirement: PermissionManager.Requirement {
    self == .inputInject ? .inputInject : .inputRead
  }
}

extension CLIFailure {
  /// A requested permission is still not granted; `missing` holds at least one id.
  static func permissionStillMissing(_ missing: [PermissionID]) -> Self {
    Self(
      .permissionMissing,
      CLILocalized.format(
        "platform.macos.cli.shared.error.permissionStillMissing",
        missing.map(\.localizedName).joined(separator: ", "),
        missing.map(\.localizedSettingsPane).joined(separator: " and ")
      )
    )
  }
}
