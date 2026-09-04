import Foundation

enum CLIParseError: LocalizedError {
  static let exitCode: Int32 = 64

  case missingCommand
  case unknownCommand(String)
  case missingSubcommand(String)
  case unexpectedArguments(command: String)

  var errorDescription: String? {
    switch self {
    case .missingCommand:
      CLILocalized.text("cli.error.missing_command", "A command is required.")
    case .unknownCommand(let command):
      CLILocalized.format("cli.error.unknown_command", "Unknown command '%@'.", command)
    case .missingSubcommand(let command):
      CLILocalized.format("cli.error.missing_subcommand", "'%@' requires a subcommand.", command)
    case .unexpectedArguments(let command):
      CLILocalized.format(
        "cli.error.unexpected_arguments",
        "'%@' does not accept additional arguments.",
        command
      )
    }
  }
}

enum CLIInvocation: Equatable {
  case help
  case version
  case status([String])
  case controllerList
  case controllerInput([String])
  case controllerOutput([String])
  case mapping([String])
  case appStatus([String])
  case appReady
  case appLogin(enable: Bool)
  case appLogs([String])
  case `extension`(CLIExtensionAction)
  case permissions([String])
  case compatibility(CLICompatibilityAction)
  case selfTest([String])
  case diagnose(CLIDiagnosticAction)
  case updateCheck([String])
}

enum CLIExtensionAction: Equatable {
  case status
  case enable
  case disable
}

enum CLICompatibilityAction: Equatable {
  case show
  case set(String)
  case reset
}

enum CLIDiagnosticAction: Equatable {
  case summary
  case runtime([String])
  case gameControllerCatalog([String])
  #if DEBUG
    case usbPassive([String])
  #endif
  case report([String])
}

struct CLIGrammar {
  let invocation: CLIInvocation
  let serviceTimeoutSeconds: Double

  init(arguments: [String]) throws {
    let parsed = try Self.parse(arguments)
    self.invocation = parsed.invocation
    self.serviceTimeoutSeconds = parsed.serviceTimeoutSeconds
  }

  func run() throws {
    let previousTimeout = CLIExecutionContext.serviceCallTimeoutSeconds
    CLIExecutionContext.serviceCallTimeoutSeconds = serviceTimeoutSeconds
    defer { CLIExecutionContext.serviceCallTimeoutSeconds = previousTimeout }

    switch invocation {
    case .help: print(CLIHelp.text)
    case .version:
      print(
        CLILocalized.format(
          "cli.help.title",
          "OpenJoystickDriver v%@ - macOS gamepad driver",
          ApplicationVersion.current
        )
      )
    case .status(let arguments), .appStatus(let arguments):
      StatusCommand().run(arguments: arguments)
    case .appReady: ApplicationServiceReadyCommand().run()
    case .controllerList: ListCommand().run()
    case .controllerInput(let arguments): InputCommand().run(arguments: arguments)
    case .controllerOutput(let arguments): PhysicalOutputCommand().run(arguments: arguments)
    case .mapping(let arguments): MappingCommand().run(arguments: arguments)
    case .appLogin(let enable):
      if enable { InstallCommand().run() } else { UninstallCommand().run() }
    case .appLogs(let arguments): LogsCommand().run(arguments: arguments)
    case .extension(let action):
      switch action {
      case .status: SystemExtensionCommand().run(arguments: ["status"])
      case .enable: SystemExtensionCommand().run(arguments: ["enable"])
      case .disable: SystemExtensionCommand().run(arguments: ["disable"])
      }
    case .permissions(let arguments): PermissionsCommand().run(arguments: arguments)
    case .compatibility(let action):
      switch action {
      case .show: CompatibilityCommand().run(arguments: ["status"])
      case .set(let identity): CompatibilityCommand().run(arguments: [identity])
      case .reset: ResetSettingsCommand().run()
      }
    case .selfTest(let arguments): SelfTestCommand().run(arguments: arguments)
    case .diagnose(let action):
      switch action {
      case .summary: DiagnoseCommand().run()
      case .runtime(let arguments): DiagnoseCommand().run(arguments: ["runtime"] + arguments)
      case .gameControllerCatalog(let arguments):
        DiagnoseCommand().run(arguments: ["catalog"] + arguments)
      #if DEBUG
        case .usbPassive(let arguments): try PassiveUSBCommand().run(arguments: arguments)
      #endif
      case .report(let arguments): ReportCommand().run(arguments: ["create"] + arguments)
      }
    case .updateCheck(let arguments): UpdatesCommand().run(arguments: ["check"] + arguments)
    }
  }

  private static func parse(_ arguments: [String]) throws -> CLIParseResult {
    let (commandArguments, serviceTimeoutSeconds) = try extractGlobalOptions(arguments)
    let invocation = try parseInvocation(commandArguments)
    return CLIParseResult(invocation: invocation, serviceTimeoutSeconds: serviceTimeoutSeconds)
  }

  private static func parseInvocation(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingCommand }
    let trailing = Array(arguments.dropFirst())

    switch command {
    case "--help", "-h":
      try requireEmpty(trailing, command: command)
      return .help
    case "--version", "-v":
      try requireEmpty(trailing, command: command)
      return .version
    case "status":
      try requireStatusOptions(trailing, command: command)
      return .status(trailing)
    case "controller": return try parseController(trailing)
    case "map":
      guard !trailing.isEmpty else { throw CLIParseError.missingSubcommand(command) }
      return .mapping(trailing)
    case "app": return try parseApp(trailing)
    case "extension": return try parseExtension(trailing)
    case "permissions": return try parsePermissions(trailing)
    case "compat": return try parseCompat(trailing)
    case "test": return .selfTest(trailing)
    case "diagnose": return try parseDiagnose(trailing)
    case "update": return try parseUpdate(trailing)
    default: throw CLIParseError.unknownCommand(command)
    }
  }

  private static func parseController(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingSubcommand("controller") }
    let trailing = Array(arguments.dropFirst())
    switch command {
    case "list":
      try requireEmpty(trailing, command: "controller list")
      return .controllerList
    case "state": return .controllerInput(["state"] + trailing)
    case "packets", "trace", "watch": return .controllerInput([command] + trailing)
    case "output": return .controllerOutput(trailing)
    default: throw CLIParseError.unknownCommand("controller \(command)")
    }
  }

  private static func parseApp(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingSubcommand("app") }
    let trailing = Array(arguments.dropFirst())
    switch command {
    case "status":
      try requireStatusOptions(trailing, command: "app status")
      return .appStatus(trailing)
    case "ready":
      try requireEmpty(trailing, command: "app ready")
      return .appReady
    case "logs": return .appLogs(trailing)
    case "login":
      guard let action = trailing.first else { throw CLIParseError.missingSubcommand("app login") }
      try requireEmpty(Array(trailing.dropFirst()), command: "app login \(action)")
      switch action {
      case "enable": return .appLogin(enable: true)
      case "disable": return .appLogin(enable: false)
      default: throw CLIParseError.unknownCommand("app login \(action)")
      }
    default: throw CLIParseError.unknownCommand("app \(command)")
    }
  }

  private static func parseExtension(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingSubcommand("extension") }
    try requireEmpty(Array(arguments.dropFirst()), command: "extension \(command)")
    switch command {
    case "status": return .extension(.status)
    case "enable": return .extension(.enable)
    case "disable": return .extension(.disable)
    default: throw CLIParseError.unknownCommand("extension \(command)")
    }
  }

  private static func parseCompat(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingSubcommand("compat") }
    let trailing = Array(arguments.dropFirst())
    switch command {
    case "show":
      try requireEmpty(trailing, command: "compat show")
      return .compatibility(.show)
    case "set":
      guard trailing.count == 1 else {
        throw CLIParseError.unexpectedArguments(command: "compat set")
      }
      return .compatibility(.set(trailing[0]))
    case "reset":
      try requireEmpty(trailing, command: "compat reset")
      return .compatibility(.reset)
    default: throw CLIParseError.unknownCommand("compat \(command)")
    }
  }

  private static func parsePermissions(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { return .permissions([]) }
    switch command {
    case "status", "request", "open", "explain", "help", "--help", "-h":
      return .permissions(arguments)
    default: throw CLIParseError.unknownCommand("permissions \(command)")
    }
  }

  private static func parseDiagnose(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { return .diagnose(.summary) }
    let trailing = Array(arguments.dropFirst())
    switch command {
    case "runtime": return .diagnose(.runtime(trailing))
    case "catalog": return .diagnose(.gameControllerCatalog(trailing)) #if DEBUG
      case "usb-passive": return .diagnose(.usbPassive(trailing))
    #endif
    case "report": return .diagnose(.report(trailing))
    default: throw CLIParseError.unknownCommand("diagnose \(command)")
    }
  }

  private static func parseUpdate(_ arguments: [String]) throws -> CLIInvocation {
    guard let command = arguments.first else { throw CLIParseError.missingSubcommand("update") }
    guard command == "check" else { throw CLIParseError.unknownCommand("update \(command)") }
    return .updateCheck(Array(arguments.dropFirst()))
  }

  private static func requireEmpty(_ arguments: [String], command: String) throws {
    guard arguments.isEmpty else { throw CLIParseError.unexpectedArguments(command: command) }
  }

  private static func requireStatusOptions(_ arguments: [String], command: String) throws {
    guard arguments.isEmpty || arguments == ["--json"] else {
      throw CLIParseError.unexpectedArguments(command: command)
    }
  }

  private static func extractGlobalOptions(_ arguments: [String]) throws -> ([String], Double) {
    var index = 0
    var timeout = 0.5
    while index < arguments.count, arguments[index] == "--timeout" {
      guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value > 0 else {
        throw CLIParseError.unexpectedArguments(command: "--timeout")
      }
      timeout = value
      index += 2
      guard index == arguments.count || arguments[index] != "--timeout" else {
        throw CLIParseError.unexpectedArguments(command: "--timeout")
      }
    }
    return (Array(arguments.dropFirst(index)), timeout)
  }
}

private struct CLIParseResult {
  let invocation: CLIInvocation
  let serviceTimeoutSeconds: Double
}

enum CLIHelp { static let text = InstalledCLIHelpRenderer.render() }
