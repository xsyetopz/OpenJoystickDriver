import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `ojd controller suspend`, `resume`, and `disconnect`.
struct ControllerSessionReport: Encodable, Equatable {
  /// The session after the command.
  ///
  /// Only `disconnect` reports `Disconnected`.
  enum Session: String, Encodable {
    /// The service drives the controller.
    case active = "Active"
    /// The service does not drive the controller until it resumes.
    case suspended = "Suspended"
    /// The controller is disconnected.
    case disconnected = "Disconnected"
  }

  /// The session ID of the controller.
  let controller: String
  /// The session after the command.
  let session: Session
  /// Whether the command changed the session.
  let changed: Bool
}

/// Prints `report` as JSON, as a `--plain` row, or as `message` on stderr.
private func printSession(_ report: ControllerSessionReport, message: String) throws {
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(report)
  case .plain:
    CLIOutput.plain([
      [report.controller, CommandLineName.kebab(report.session.rawValue), String(report.changed)]
    ])
  case .human: CLIOutput.success(message)
  }
}

/// The failure for a controller that has no session.
private func sessionNotFound(_ selector: ControllerSelector) -> CLIFailure {
  CLIFailure(
    .controllerRequestFailed,
    CLILocalized.format(
      "cli.controller.group.sessionNotFound",
      selector.text
    )
  )
}

/// The `ojd controller suspend` command: stops OJD from driving a controller until it resumes.
struct ControllerSuspendCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "suspend",
    abstract: CLILocalized.text(
      "cli.controller.suspend.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to suspend.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.suspendController(.session(device.sessionToken))
        return (device, result)
      }
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw sessionNotFound(selector)
      }
      try printSession(
        ControllerSessionReport(
          controller: device.sessionToken.rawValue,
          session: .suspended,
          changed: result.succeeded
        ),
        message: result.succeeded
          ? CLILocalized.format("cli.controller.suspend.done", device.name)
          : CLILocalized.format(
            "cli.controller.suspend.already",
            device.name
          )
      )
    }
  }
}

/// The `ojd controller resume` command: lets OJD drive a suspended controller again.
struct ControllerResumeCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "resume",
    abstract: CLILocalized.text(
      "cli.controller.resume.abstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to resume.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.resumeController(.session(device.sessionToken))
        return (device, result)
      }
      guard result.succeeded || result.failure == .alreadyActive else {
        throw sessionNotFound(selector)
      }
      try printSession(
        ControllerSessionReport(
          controller: device.sessionToken.rawValue,
          session: .active,
          changed: result.succeeded
        ),
        message: result.succeeded
          ? CLILocalized.format("cli.controller.resume.done", device.name)
          : CLILocalized.format(
            "cli.controller.resume.already",
            device.name
          )
      )
    }
  }
}

/// The `ojd controller disconnect` command: closes a classic Bluetooth controller's connection.
struct ControllerDisconnectCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "disconnect",
    abstract: CLILocalized.text(
      "cli.controller.disconnect.abstract"
    ),
    discussion: CLILocalized.text(
      "platform.macos.cli.controller.disconnect.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to disconnect.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let selector = controller
      let timeout = max(
        ServiceTimeouts.bluetoothDisconnectRequest,
        CLIContext.current.requestTimeout
      )
      let (device, result) = try await ServiceConnection.request(timeout: timeout) { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.disconnectWirelessController(.session(device.sessionToken))
        return (device, result)
      }
      guard result.succeeded else { throw Self.failure(result, device) }
      try printSession(
        ControllerSessionReport(
          controller: device.sessionToken.rawValue,
          session: .disconnected,
          changed: true
        ),
        message: CLILocalized.format(
          "cli.controller.disconnect.done",
          device.name
        )
      )
    }
  }

  /// The failure for a disconnect that did not succeed, named for the controller.
  static func failure(
    _ result: WirelessControllerDisconnectResult,
    _ device: ApplicationServiceDeviceDescription
  ) -> CLIFailure {
    switch result.failure {
    case .notBluetooth:
      return CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "cli.controller.disconnect.notBluetooth",
          device.name
        )
      )
    case .bluetoothLEUnsupported:
      return CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "platform.macos.cli.controller.disconnect.bluetoothLe",
          device.name
        )
      )
    case .notFound:
      return CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "cli.controller.group.sessionNotFound",
          device.sessionToken.rawValue
        )
      )
    default:
      let stage = result.failedStage?.rawValue ?? "disconnect"
      let cause = result.detail ?? result.failure?.rawValue ?? "unknown"
      let code = result.systemCode.map { " (system code \($0))" } ?? ""
      let recovery = result.recovery.map { " \($0)" } ?? ""
      return CLIFailure(
        .controllerRequestFailed,
        CLILocalized.format(
          "cli.controller.disconnect.failed",
          stage,
          cause + code
        ) + recovery
      )
    }
  }
}
