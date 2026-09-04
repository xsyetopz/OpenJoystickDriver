enum CommandAudience: String, Sendable {
  case user
  case advanced
  case support
}

enum CommandSideEffect: String, Sendable {
  case readOnly
  case streamingRead
  case transientDeviceMutation
  case persistentConfiguration
  case systemMutation
  case networkRead
}

enum CommandOutput: String, Sendable {
  case text
  case json
  case jsonLines
}

struct CommandDefinition: Sendable {
  let path: String
  let summary: String
  let group: String
  let audience: CommandAudience
  let sideEffect: CommandSideEffect
  let outputs: Set<CommandOutput>
}

enum InstalledCommandCatalog {
  static let commands: [CommandDefinition] = [
    command(
      "status [--json]",
      CLILocalized.text("cli.catalog.status.summary", "Show driver and runtime status"),
      group: CLILocalized.text("cli.catalog.group.overview", "Overview"),
      outputs: [.text, .json]
    ),
    command(
      "app status [--json]",
      CLILocalized.text("cli.catalog.app_status.summary", "Show application-service status"),
      group: CLILocalized.text("cli.catalog.group.overview", "Overview"),
      outputs: [.text, .json]
    ),
    command(
      "app ready",
      CLILocalized.text(
        "cli.catalog.app_ready.summary",
        "Check authenticated application-service readiness"
      ),
      group: CLILocalized.text("cli.catalog.group.overview", "Overview"),
      audience: .support
    ),
    command(
      "controller list",
      CLILocalized.text("cli.catalog.controller_list.summary", "List connected controllers"),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers")
    ),
    command(
      "controller state [options]",
      CLILocalized.text("cli.catalog.controller_state.summary", "Show current controller state"),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers"),
      outputs: [.text, .json]
    ),
    command(
      "controller packets [options]",
      CLILocalized.text("cli.catalog.controller_packets.summary", "Show recent controller packets"),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers"),
      audience: .advanced,
      outputs: [.text, .json]
    ),
    command(
      "controller trace [options]",
      CLILocalized.text("cli.catalog.controller_trace.summary", "Watch raw controller packets"),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers"),
      audience: .advanced,
      sideEffect: .streamingRead,
      outputs: [.text, .jsonLines]
    ),
    command(
      "controller watch [options]",
      CLILocalized.text("cli.catalog.controller_watch.summary", "Watch controller input changes"),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers"),
      audience: .advanced,
      sideEffect: .streamingRead,
      outputs: [.text, .jsonLines]
    ),
    command(
      "controller output <command> [options]",
      CLILocalized.text(
        "cli.catalog.controller_output.summary",
        "Test supported physical controller output"
      ),
      group: CLILocalized.text("cli.catalog.group.controllers", "Controllers"),
      audience: .advanced,
      sideEffect: .transientDeviceMutation
    ),
    command(
      "map <command> [options]",
      CLILocalized.text("cli.catalog.map.summary", "Manage controller mapping profiles"),
      group: CLILocalized.text("cli.catalog.group.configuration", "Configuration"),
      audience: .advanced,
      sideEffect: .persistentConfiguration,
      outputs: [.text, .json]
    ),
    command(
      "compat show|reset | compat set <identity>",
      CLILocalized.text("cli.catalog.compat.summary", "Manage virtual-controller compatibility"),
      group: CLILocalized.text("cli.catalog.group.configuration", "Configuration"),
      sideEffect: .persistentConfiguration
    ),
    command(
      "permissions [status|request|open|explain]",
      CLILocalized.text(
        "cli.catalog.permissions.summary",
        "Review or request required permissions"
      ),
      group: CLILocalized.text("cli.catalog.group.system", "System"),
      audience: .support,
      sideEffect: .systemMutation
    ),
    command(
      "app login enable|disable",
      CLILocalized.text("cli.catalog.login.summary", "Manage login-item registration"),
      group: CLILocalized.text("cli.catalog.group.system", "System"),
      sideEffect: .systemMutation
    ),
    command(
      "app logs [show|path|open] [options]",
      CLILocalized.text("cli.catalog.logs.summary", "Review application-service logs"),
      group: CLILocalized.text("cli.catalog.group.support", "Support"),
      audience: .support,
      outputs: [.text, .json]
    ),
    command(
      "extension status|enable|disable",
      CLILocalized.text("cli.catalog.extension.summary", "Manage the DriverKit system extension"),
      group: CLILocalized.text("cli.catalog.group.support", "Support"),
      audience: .support,
      sideEffect: .systemMutation
    ),
    command(
      "diagnose [runtime|catalog|report]",
      CLILocalized.text(
        "cli.catalog.diagnose.summary",
        "Run focused diagnostics or create a report"
      ),
      group: CLILocalized.text("cli.catalog.group.support", "Support"),
      audience: .support,
      outputs: [.text, .json]
    ),
    command(
      "test [positive-seconds]",
      CLILocalized.text("cli.catalog.test.summary", "Test virtual-controller input delivery"),
      group: CLILocalized.text("cli.catalog.group.support", "Support"),
      audience: .support,
      sideEffect: .transientDeviceMutation
    ),
    command(
      "update check [options]",
      CLILocalized.text("cli.catalog.update.summary", "Check GitHub for available updates"),
      group: CLILocalized.text("cli.catalog.group.support", "Support"),
      sideEffect: .networkRead,
      outputs: [.text, .json]
    )
  ]

  private static func command(
    _ path: String,
    _ summary: String,
    group: String,
    audience: CommandAudience = .user,
    sideEffect: CommandSideEffect = .readOnly,
    outputs: Set<CommandOutput> = [.text]
  ) -> CommandDefinition {
    CommandDefinition(
      path: path,
      summary: summary,
      group: group,
      audience: audience,
      sideEffect: sideEffect,
      outputs: outputs
    )
  }
}

enum InstalledCLIHelpRenderer {
  static func render(commands: [CommandDefinition] = InstalledCommandCatalog.commands) -> String {
    var lines = [
      CLILocalized.format(
        "cli.help.title",
        "OpenJoystickDriver v%@ - macOS gamepad driver",
        ApplicationVersion.current
      ), "",
      CLILocalized.text(
        "cli.help.usage",
        "Usage: OpenJoystickDriver --headless [--timeout <seconds>] <command>"
      ), ""
    ]
    var currentGroup: String?
    for command in commands {
      if command.group != currentGroup {
        if currentGroup != nil { lines.append("") }
        lines.append("\(command.group):")
        currentGroup = command.group
      }
      lines.append("  \(command.path)")
      lines.append("    \(command.summary).")
    }
    lines += [
      "", CLILocalized.text("cli.help.options.heading", "Options:"),
      CLILocalized.text(
        "cli.help.timeout",
        "  --timeout <seconds>  Set the local application-service timeout"
      ), CLILocalized.text("cli.help.help", "  -h, --help           Show this help"),
      CLILocalized.text("cli.help.version", "  -v, --version        Show version"), "",
      CLILocalized.text(
        "cli.help.json",
        "Use --json for machine-readable output where supported and --device <id>"
      ),
      CLILocalized.text(
        "cli.help.device",
        "for controller-scoped operations. Output never relies on color alone."
      )
    ]
    return lines.joined(separator: "\n")
  }
}
