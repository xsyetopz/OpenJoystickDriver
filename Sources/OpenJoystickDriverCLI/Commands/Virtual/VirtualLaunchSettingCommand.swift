public import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd virtual launch-setting` command group: list, show, set and remove what `ojd virtual
/// launch` applies to a program.
struct VirtualLaunchSettingCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "launch-setting",
    abstract: CLILocalized.text("cli.virtual.launchSetting.group.abstract"),
    discussion: CLILocalized.text("cli.virtual.launchSetting.group.discussion"),
    subcommands: [
      VirtualLaunchSettingListCommand.self, VirtualLaunchSettingShowCommand.self,
      VirtualLaunchSettingSetCommand.self, VirtualLaunchSettingRemoveCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// One launch setting in `--json` output.
struct LaunchSettingSummary: Encodable, Equatable {
  /// The key of the setting: a bundle identifier, or the absolute path of a program outside a
  /// bundle.
  let program: String
  /// Whether the program starts with the SDL GameController backend hints.
  let sdlGameControllerBackend: Bool
  /// The variables added to the program's environment.
  let environment: [String: String]
  /// The arguments appended after the arguments given on the command line.
  let arguments: [String]

  /// Creates the summary of `setting`, stored under `key`.
  init(key: String, _ setting: LaunchSetting) {
    program = key
    sdlGameControllerBackend = setting.sdlGameControllerBackend
    environment = setting.environment
    arguments = setting.arguments
  }

  /// The `NAME=VALUE` lines of the environment, sorted by name.
  var environmentLines: [String] {
    environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
  }

  /// Prints the setting in the format of the command.
  func print() throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(self)
    case .plain:
      CLIOutput.plain(
        [[program, "sdl-gamecontroller-backend", String(sdlGameControllerBackend)]]
          + environmentLines.map { [program, "env", $0] }
          + arguments.map { [program, "argument", $0] }
      )
    case .human:
      CLIOutput.stdout(program)
      CLIOutput.stdout("  sdl-gamecontroller-backend: \(sdlGameControllerBackend)")
      for line in environmentLines { CLIOutput.stdout("  env: \(line)") }
      for argument in arguments { CLIOutput.stdout("  argument: \(argument)") }
    }
  }
}

/// How the commands of the group find and change the stored launch settings.
enum LaunchSettingCatalog {
  /// The key that `program` names.
  ///
  /// A program that no longer exists still names a stored setting by its key, so a setting of a
  /// deleted app can be shown and removed.
  ///
  /// - Throws: ``CLIFailure`` when `program` has no executable and is no stored key.
  static func key(for program: String, stored: [String: LaunchSetting]) throws -> String {
    do {
      return try LaunchSettingKey.key(
        for: program,
        searchPath: VirtualLaunchCommand.baseEnvironment["PATH"]
      )
    } catch {
      if stored[program] != nil { return program }
      _ = try ProgramLauncher.executable(
        for: program,
        searchPath: VirtualLaunchCommand.baseEnvironment["PATH"]
      )
      throw error
    }
  }

  /// The failure for a change that ``LaunchSettingError`` refuses.
  static func failure(_ error: LaunchSettingError) -> CLIFailure {
    switch error {
    case .invalidEnvironmentName(let name):
      .usage(CLILocalized.format("cli.virtual.launchSetting.group.errorName", name))
    case .invalidEnvironmentAssignment(let text):
      .usage(CLILocalized.format("cli.virtual.launchSetting.group.errorAssignment", text))
    }
  }
}

/// The PROGRAM argument of the commands that take one.
private let programArgumentHelp = ArgumentHelp(
  CLILocalized.text("cli.virtual.launchSetting.group.program"),
  valueName: "program"
)

/// The `ojd virtual launch-setting list` command: prints every stored launch setting.
struct VirtualLaunchSettingListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.virtual.launchSetting.list.abstract")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let summaries = try SettingCatalog.store.launchSettings().sorted { $0.key < $1.key }
        .map { LaunchSettingSummary(key: $0.key, $0.value) }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIList(items: summaries))
      case .plain:
        CLIOutput.plain(
          summaries.map {
            [
              $0.program, String($0.sdlGameControllerBackend), String($0.environment.count),
              String($0.arguments.count),
            ]
          }
        )
      case .human:
        if summaries.isEmpty {
          CLIOutput.stderr(CLILocalized.text("cli.virtual.launchSetting.list.empty"))
        }
        for summary in summaries {
          CLIOutput.stdout(
            "\(summary.program)  sdl-gamecontroller-backend:\(summary.sdlGameControllerBackend)"
              + "  env:\(summary.environment.count)  arguments:\(summary.arguments.count)"
          )
        }
      }
    }
  }
}

/// The `ojd virtual launch-setting show` command: prints the launch setting of one program.
struct VirtualLaunchSettingShowCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: CLILocalized.text("cli.virtual.launchSetting.show.abstract")
  )

  /// The program, or the key of a stored setting.
  @Argument(help: programArgumentHelp)
  var program: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let stored = try SettingCatalog.store.launchSettings()
      let key = try LaunchSettingCatalog.key(for: program, stored: stored)
      guard let setting = stored[key] else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.virtual.launchSetting.group.errorMissing", key)
        )
      }
      try LaunchSettingSummary(key: key, setting).print()
    }
  }
}

/// The `ojd virtual launch-setting set` command: stores the launch setting of one program.
struct VirtualLaunchSettingSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.virtual.launchSetting.set.abstract")
  )

  /// The program, or the key of a stored setting.
  @Argument(help: programArgumentHelp)
  var program: String

  /// `--sdl-gamecontroller-backend` or `--no-sdl-gamecontroller-backend`.
  @Flag(
    name: .customLong("sdl-gamecontroller-backend"),
    inversion: .prefixedNo,
    help: ArgumentHelp(CLILocalized.text("cli.virtual.launchSetting.set.backend"))
  )
  var sdlGameControllerBackend: Bool?

  /// `--env`: one variable written `NAME=VALUE`; repeat for more.
  @Option(
    name: .customLong("env"),
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.launchSetting.set.env"),
      valueName: "name=value"
    )
  )
  var environment: [String] = []

  /// `--argument`: one argument; repeat for more.
  @Option(
    name: .customLong("argument"),
    parsing: .unconditionalSingleValue,
    help: ArgumentHelp(
      CLILocalized.text("cli.virtual.launchSetting.set.argument"),
      valueName: "argument"
    )
  )
  var arguments: [String] = []

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let store = SettingCatalog.store
      let stored = try store.launchSettings()
      let key = try LaunchSettingCatalog.key(for: program, stored: stored)
      var setting = stored[key] ?? LaunchSetting()
      do {
        if let sdlGameControllerBackend {
          setting.sdlGameControllerBackend = sdlGameControllerBackend
        }
        if !environment.isEmpty {
          setting.environment = Dictionary(
            try environment.map(LaunchSetting.assignment).map { ($0.name, $0.value) }
          ) { _, last in last }
        }
        if !arguments.isEmpty { setting.arguments = arguments }
        try store.setLaunchSetting(setting, for: key)
      } catch let error as LaunchSettingError { throw LaunchSettingCatalog.failure(error) }
      if case .human = CLIContext.current.format {
        CLIOutput.success(CLILocalized.format("cli.virtual.launchSetting.set.done", key))
      } else {
        try LaunchSettingSummary(key: key, setting).print()
      }
    }
  }
}

/// The `ojd virtual launch-setting remove` command: removes the launch setting of one program.
struct VirtualLaunchSettingRemoveCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: CLILocalized.text("cli.virtual.launchSetting.remove.abstract")
  )

  /// The `--json` result of `launch-setting remove`.
  struct Result: Encodable, Equatable {
    /// The key of the removed setting.
    let removed: String
  }

  /// The program, or the key of a stored setting.
  @Argument(help: programArgumentHelp)
  var program: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let store = SettingCatalog.store
      let key = try LaunchSettingCatalog.key(for: program, stored: try store.launchSettings())
      guard try store.removeLaunchSetting(for: key) else {
        throw CLIFailure(
          .notFound,
          CLILocalized.format("cli.virtual.launchSetting.group.errorMissing", key)
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: Result(removed: key)))
      case .plain: CLIOutput.plain([[key]])
      case .human:
        CLIOutput.success(CLILocalized.format("cli.virtual.launchSetting.remove.done", key))
      }
    }
  }
}
