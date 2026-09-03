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
      "Show driver and runtime status",
      group: "Overview",
      outputs: [.text, .json]
    ),
    command(
      "app status [--json]",
      "Show application-service status",
      group: "Overview",
      outputs: [.text, .json]
    ), command(
      "app ready",
      "Check authenticated application-service readiness",
      group: "Overview",
      audience: .support
    ), command("controller list", "List connected controllers", group: "Controllers"),
    command(
      "controller state [options]",
      "Show current controller state",
      group: "Controllers",
      outputs: [.text, .json]
    ),
    command(
      "controller packets [options]",
      "Show recent controller packets",
      group: "Controllers",
      audience: .advanced,
      outputs: [.text, .json]
    ),
    command(
      "controller trace [options]",
      "Watch newly captured raw controller packets",
      group: "Controllers",
      audience: .advanced,
      sideEffect: .streamingRead,
      outputs: [.text, .jsonLines]
    ),
    command(
      "controller watch [options]",
      "Watch controller input changes",
      group: "Controllers",
      audience: .advanced,
      sideEffect: .streamingRead,
      outputs: [.text, .jsonLines]
    ),
    command(
      "controller output <command> [options]",
      "Test supported physical controller output",
      group: "Controllers",
      audience: .advanced,
      sideEffect: .transientDeviceMutation
    ),
    command(
      "map <command> [options]",
      "Manage controller mapping profiles",
      group: "Configuration",
      audience: .advanced,
      sideEffect: .persistentConfiguration,
      outputs: [.text, .json]
    ),
    command(
      "compat show|reset | compat set <identity>",
      "Manage virtual-controller compatibility",
      group: "Configuration",
      sideEffect: .persistentConfiguration
    ),
    command(
      "permissions [status|request|open|explain]",
      "Review or request required permissions",
      group: "System",
      audience: .support,
      sideEffect: .systemMutation
    ),
    command(
      "app login enable|disable",
      "Manage login-item registration",
      group: "System",
      sideEffect: .systemMutation
    ),
    command(
      "app logs [show|path|open] [options]",
      "Review application-service logs",
      group: "Support",
      audience: .support,
      outputs: [.text, .json]
    ),
    command(
      "extension status|enable|disable",
      "Manage the DriverKit system extension",
      group: "Support",
      audience: .support,
      sideEffect: .systemMutation
    ),
    command(
      "diagnose [runtime|catalog|report]",
      "Run focused diagnostics or create a report",
      group: "Support",
      audience: .support,
      outputs: [.text, .json]
    ),
    command(
      "test [positive-seconds]",
      "Test virtual-controller input delivery",
      group: "Support",
      audience: .support,
      sideEffect: .transientDeviceMutation
    ),
    command(
      "update check [options]",
      "Check GitHub for available updates",
      group: "Support",
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
      "OpenJoystickDriver v\(ApplicationVersion.current) - macOS gamepad driver", "",
      "Usage: OpenJoystickDriver --headless [--timeout <seconds>] <command>", ""
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
      "", "Options:", "  --timeout <seconds>  Set the local application-service timeout",
      "  -h, --help           Show this help", "  -v, --version        Show version", "",
      "Use --json for machine-readable output where supported and --device <id>",
      "for controller-scoped operations. Output never relies on color alone."
    ]
    return lines.joined(separator: "\n")
  }
}
