import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct AccessWebCommand: AsyncParsableCommand {
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

  @OptionGroup
  var global: GlobalOptions
}

struct AccessWebEnableCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "enable",
    abstract: CLILocalized.text("cli.access.web.enable.abstract"),
    discussion: CLILocalized.text(
      "cli.access.web.enable.discussion"
    )
  )

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text("cli.access.web.port"),
      valueName: "port"
    )
  )
  var port: Int?

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @OptionGroup
  var global: GlobalOptions

  func validate() throws {
    if let port, !(1_024...65_535).contains(port) {
      throw ValidationError(
        CLILocalized.text("cli.access.web.port_range")
      )
    }
  }

  func run() async throws {
    try await global.run {
      try CLITerminal.confirm(
        CLILocalized.text(
          "cli.access.web.enable.confirm"
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
      "cli.access.web.disable.abstract"
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
            "cli.access.web.disable.success"
          )
      )
    }
  }
}
