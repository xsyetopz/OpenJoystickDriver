import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd access web` command group: turn the endpoint's WebSocket on or off.
struct AccessWebCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "web",
    abstract: CLILocalized.text(
      "cli.access.web.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.web.discussion"
    ),
    subcommands: [AccessWebEnableCommand.self, AccessWebDisableCommand.self]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The `ojd access web enable` command: turns on the WebSocket on `127.0.0.1` after a confirmation.
///
/// Without `--port` it uses the saved port, and the first time the system picks a free port.
struct AccessWebEnableCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.web.enableAbstract"),
    discussion: CLILocalized.text(
      "cli.access.web.enableDiscussion"
    )
  )

  /// `--port`: the port to listen on, within the allowed range.
  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text("cli.access.web.port"),
      valueName: "port"
    )
  )
  var port: Int?

  /// `--automatic`: let the system pick a free port even when one is saved; it cannot be combined
  /// with `--port`.
  @Flag(
    name: .long,
    help: ArgumentHelp(CLILocalized.text("cli.access.web.automatic"))
  )
  var automatic = false

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that `--automatic` does not come with a port and that the port is allowed.
  ///
  /// - Throws: ``ValidationError`` otherwise.
  func validate() throws {
    if automatic, port != nil {
      throw ValidationError(CLILocalized.text("cli.access.web.automaticConflict"))
    }
    if let port, !AccessWebPorts.allowed.contains(port) {
      throw ValidationError(
        CLILocalized.text("cli.access.web.portRange")
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.web.enableConfirm"
        ),
        force: force,
        needsForce: AccessText.needsForce
      )
      let port = automatic ? 0 : port
      let status = try await ServiceConnection.request {
        try await $0.setWebAccess(enabled: true, port: port)
      }
      try AccessWebCommand.print(status.web)
    }
  }
}

/// The `ojd access web disable` command: turns off the WebSocket and closes its connections.
///
/// The tokens stay.
struct AccessWebDisableCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: CLILocalized.text(
      "cli.access.web.disableAbstract"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let status = try await ServiceConnection.request {
        try await $0.setWebAccess(enabled: false, port: nil)
      }
      try AccessWebCommand.print(status.web)
    }
  }
}

extension AccessWebCommand {
  /// Prints the result of `web enable` and `web disable`.
  static func print(_ web: AccessWebStatus) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(web)
    case .plain: CLIOutput.plain([[String(web.enabled), String(web.listening), web.url ?? ""]])
    case .human:
      CLIOutput.success(
        web.enabled
          ? AccessText.web(web)
          : CLILocalized.text(
            "cli.access.web.disableSuccess"
          )
      )
    }
  }
}
