import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `--json` result of `ojd controller suspend`, `resume`, and `disconnect`.
struct ControllerSessionReport: Encodable, Equatable {
  /// The session after the command. Only `disconnect` reports `disconnected`.
  enum Session: String, Encodable {
    case active
    case suspended
    case disconnected
  }

  let controller: String
  let session: Session
  let changed: Bool
}

private func printSession(_ report: ControllerSessionReport, message: String) throws {
  switch CLIContext.current.format {
  case .json: try CLIOutput.json(report)
  case .plain:
    CLIOutput.plain([[report.controller, report.session.rawValue, String(report.changed)]])
  case .human: CLIOutput.success(message)
  }
}

private func sessionNotFound(_ selector: ControllerSelector) -> CLIFailure {
  CLIFailure(
    .failure,
    CLILocalized.format(
      "cli.controller.session.not_found",
      "'%@' disconnected before the request reached it. Reconnect it and retry.",
      selector.text
    )
  )
}

struct ControllerSuspendCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "suspend",
    abstract: CLILocalized.text(
      "cli.controller.suspend.abstract",
      "Stop OpenJoystickDriver from driving a controller until you resume it."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  func run() async throws {
    try await global.run {
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.suspendController(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
        return (device, result)
      }
      guard result.succeeded || result.failure == .alreadySuspended else {
        throw sessionNotFound(selector)
      }
      try printSession(
        ControllerSessionReport(
          controller: device.runtimeIdentifier,
          session: .suspended,
          changed: result.succeeded
        ),
        message: result.succeeded
          ? CLILocalized.format("cli.controller.suspend.done", "Suspended %@.", device.name)
          : CLILocalized.format(
            "cli.controller.suspend.already",
            "%@ is already suspended.",
            device.name
          )
      )
    }
  }
}

struct ControllerResumeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "resume",
    abstract: CLILocalized.text(
      "cli.controller.resume.abstract",
      "Let OpenJoystickDriver drive a suspended controller again."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  func run() async throws {
    try await global.run {
      let selector = controller
      let (device, result) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.resumeController(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
        return (device, result)
      }
      guard result.succeeded || result.failure == .alreadyActive else {
        throw sessionNotFound(selector)
      }
      try printSession(
        ControllerSessionReport(
          controller: device.runtimeIdentifier,
          session: .active,
          changed: result.succeeded
        ),
        message: result.succeeded
          ? CLILocalized.format("cli.controller.resume.done", "Resumed %@.", device.name)
          : CLILocalized.format(
            "cli.controller.resume.already",
            "%@ is already active.",
            device.name
          )
      )
    }
  }
}

struct ControllerDisconnectCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "disconnect",
    abstract: CLILocalized.text(
      "cli.controller.disconnect.abstract",
      "Disconnect a Bluetooth controller."
    ),
    discussion: CLILocalized.text(
      "cli.controller.disconnect.discussion",
      "Closes the Bluetooth connection. The controller stays paired and reconnects when you "
        + "turn it on again. Waits at least 6 seconds for Bluetooth to confirm."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The service waits up to 5 seconds for Bluetooth; this leaves room for its reply.
  static let minimumTimeout: Double = 6

  func run() async throws {
    try await global.run {
      let selector = controller
      let timeout = max(Self.minimumTimeout, CLIContext.current.requestTimeout)
      let (device, result) = try await ServiceConnection.request(timeout: timeout) { client in
        let device = try await selector.resolve(with: client)
        let result = try await client.disconnectWirelessController(
          vendorID: device.vendorID,
          productID: device.productID,
          runtimeIdentifier: device.runtimeIdentifier
        )
        return (device, result)
      }
      guard result.succeeded else { throw Self.failure(result, device) }
      try printSession(
        ControllerSessionReport(
          controller: device.runtimeIdentifier,
          session: .disconnected,
          changed: true
        ),
        message: CLILocalized.format(
          "cli.controller.disconnect.done",
          "Disconnected %@.",
          device.name
        )
      )
    }
  }

  static func failure(
    _ result: WirelessControllerDisconnectResult,
    _ device: ApplicationServiceDeviceDescription
  ) -> CLIFailure {
    switch result.failure {
    case .notBluetooth:
      return CLIFailure(
        .failure,
        CLILocalized.format(
          "cli.controller.disconnect.not_bluetooth",
          "%@ is not connected over Bluetooth. Unplug it to disconnect it.",
          device.name
        )
      )
    case .notFound:
      return CLIFailure(
        .failure,
        CLILocalized.format(
          "cli.controller.session.not_found",
          "'%@' disconnected before the request reached it. Reconnect it and retry.",
          device.runtimeIdentifier
        )
      )
    default:
      let stage = result.failedStage?.rawValue ?? "disconnect"
      let cause = result.detail ?? result.failure?.rawValue ?? "unknown"
      let code = result.systemCode.map { " (system code \($0))" } ?? ""
      let recovery = result.recovery.map { " \($0)" } ?? ""
      return CLIFailure(
        .failure,
        CLILocalized.format(
          "cli.controller.disconnect.failed",
          "Bluetooth disconnect failed during %@: %@.",
          stage,
          cause + code
        ) + recovery
      )
    }
  }
}
