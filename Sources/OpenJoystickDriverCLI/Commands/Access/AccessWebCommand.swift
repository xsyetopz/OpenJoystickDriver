import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct AccessWebCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "web",
    abstract: CLILocalized.text(
      "cli.access.web.abstract",
      "Turn the WebSocket for overlay pages on or off."
    ),
    discussion: CLILocalized.text(
      "cli.access.web.discussion",
      "The WebSocket listens on 127.0.0.1 only, at /endpoint, and serves the files of its "
        + "Overlays folder on the same port. A page must come from an origin that a token is "
        + "granted for, and must sign the service's challenge with that token in its hello; "
        + "grant one with 'ojd access grant --token NAME --origin URL'."
    ),
    subcommands: [AccessWebEnableCommand.self, AccessWebDisableCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

struct AccessWebEnableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.web.enable.abstract", "Turn on the WebSocket."),
    discussion: CLILocalized.text(
      "cli.access.web.enable.discussion",
      "Asks for confirmation first. Without --port, uses the saved port; the first time, the "
        + "system picks a free port, and the service saves it."
    )
  )

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text("cli.access.web.port", "The port on 127.0.0.1, from 1024 to 65535."),
      valueName: "port"
    )
  )
  var port: Int?

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @OptionGroup
  var global: GlobalOptions

  func validate() throws {
    if let port, !(1_024...65_535).contains(port) {
      throw ValidationError(
        CLILocalized.text("cli.access.web.port_range", "--port must be between 1024 and 65535.")
      )
    }
  }

  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.web.enable.confirm",
          "Turn on the WebSocket, so that pages from the origins you grant tokens for can use "
            + "the endpoint?"
        ),
        force: force,
        needsForce: AccessText.needsForce
      )
      let port = port
      let status = try await ServiceConnection.request {
        try await $0.setWebAccess(enabled: true, port: port)
      }
      try AccessWebCommand.print(status.web)
    }
  }
}

struct AccessWebDisableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "disable",
    abstract: CLILocalized.text(
      "cli.access.web.disable.abstract",
      "Turn off the WebSocket and close its connections; tokens are kept."
    )
  )

  @OptionGroup
  var global: GlobalOptions

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
            "cli.access.web.disable.success",
            "The WebSocket is off, and its connections are closed."
          )
      )
    }
  }
}
