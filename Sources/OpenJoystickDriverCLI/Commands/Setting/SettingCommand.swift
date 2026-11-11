import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd setting` command group: list, read, change and reset the application settings, and send
/// a test notification.
struct SettingCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "setting",
    abstract: CLILocalized.text(
      "cli.setting.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.setting.group.discussion"
    ),
    subcommands: [
      SettingListCommand.self, SettingGetCommand.self, SettingSetCommand.self,
      SettingResetCommand.self, SettingTestNotificationCommand.self,
    ]
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The settings `ojd setting` names, with their help text and value parsing.
enum SettingCatalog {
  /// The help text of `key`.
  static func description(of key: ApplicationSettingKey) -> String {
    switch key {
    case .launchAtLogin:
      CLILocalized.text("cli.setting.group.launchAtLogin")
    case .showInMenuBar:
      CLILocalized.text("cli.setting.group.showInMenuBar")
    case .showInDock:
      CLILocalized.text("platform.macos.cli.setting.group.showInDock")
    case .notifyControllerConnected:
      CLILocalized.text("cli.setting.group.notifyControllerConnected")
    case .notifyControllerDisconnected:
      CLILocalized.text("cli.setting.group.notifyControllerDisconnected")
    case .notifyProfileActivated:
      CLILocalized.text("cli.setting.group.notifyProfileActivated")
    case .notifyProfileDeactivated:
      CLILocalized.text("cli.setting.group.notifyProfileDeactivated")
    case .notifySounds:
      CLILocalized.text("cli.setting.group.notificationSounds")
    case .updatesCheckAutomatically:
      CLILocalized.text("cli.setting.group.checkUpdatesAutomatically")
    case .updatesIncludePrereleases:
      CLILocalized.text(
        "cli.setting.group.includePrereleaseUpdates"
      )
    case .developerTools:
      CLILocalized.text(
        "cli.setting.group.developerTools"
      )
    }
  }

  /// The name of the pause shortcut, the one setting that holds text and not true or false.
  static let pauseShortcutName = "pauseShortcut"

  /// The text that clears the pause shortcut.
  static let noShortcut = "none"

  /// The settings file the pause shortcut is read from and written to; tests point it at a
  /// temporary folder.
  @TaskLocal
  static var store = SettingsStore()

  /// The names of every setting, as shown in help and error text.
  static var keyNames: String {
    (ApplicationSettingKey.allCases.map(\.rawValue) + [pauseShortcutName]).joined(separator: ", ")
  }

  /// Checks that `name` names a setting.
  ///
  /// - Throws: ``ValidationError`` when no setting has that name.
  static func validate(name: String) throws {
    if name != pauseShortcutName { _ = try key(name) }
  }

  /// Parses `text` as the pause shortcut, or `none` for no shortcut.
  ///
  /// - Throws: ``ValidationError`` when `text` is neither.
  static func pauseShortcut(_ text: String) throws -> PauseShortcut? {
    guard text != noShortcut else { return nil }
    do { return try PauseShortcut(parsing: text) } catch {
      throw ValidationError(CLILocalized.format("cli.setting.set.badShortcut", text))
    }
  }

  /// Prints the pause shortcut `value` as `key` and `value` JSON, or as the text alone.
  static func printPauseShortcut(_ shortcut: PauseShortcut?) throws {
    let text = shortcut?.text ?? noShortcut
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(PauseShortcutResult(key: pauseShortcutName, value: text))
    case .plain, .human: CLIOutput.stdout(text)
    }
  }

  /// Returns the setting that `name` names.
  ///
  /// - Throws: ``ValidationError`` when no setting has that name.
  static func key(_ name: String) throws -> ApplicationSettingKey {
    guard let key = ApplicationSettingKey(rawValue: name) else {
      throw ValidationError(
        CLILocalized.format(
          "cli.setting.group.unknownKey",
          name,
          keyNames
        )
      )
    }
    return key
  }

  /// Parses `text` as the value of `key`, which is `true` or `false`.
  ///
  /// - Throws: ``ValidationError`` when `text` is neither.
  static func value(_ text: String, for key: ApplicationSettingKey) throws -> Bool {
    switch text {
    case "true": return true
    case "false": return false
    default:
      throw ValidationError(
        CLILocalized.format(
          "cli.setting.group.badValue",
          text,
          key.rawValue
        )
      )
    }
  }

  /// Reads every setting from the service.
  static func read() async throws -> ApplicationSettingsPayload {
    try await ServiceConnection.request { client in try await client.getSettings() }
  }
}

/// The `--json` result of `setting get` and `setting set`.
struct SettingResult: Encodable, Equatable {
  /// The setting name.
  let key: String
  /// The setting value.
  let value: Bool

  /// Prints `key` and `value` as JSON, or as the value alone.
  static func print(_ key: ApplicationSettingKey, value: Bool) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(Self(key: key.rawValue, value: value))
    case .plain, .human: CLIOutput.stdout(String(value))
    }
  }
}

/// The `--json` result of `setting get` and `setting set` for the pause shortcut.
struct PauseShortcutResult: Encodable, Equatable {
  /// The setting name.
  let key: String
  /// The shortcut as `control+option+P`, or `none`.
  let value: String
}

/// The `ojd setting list` command: prints every setting with its value and description.
struct SettingListCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.setting.list.abstract")
  )

  /// One setting in the `--json` result.
  struct Entry: Encodable, Equatable {
    /// The setting name.
    let key: String
    /// The setting value.
    let value: Bool
    /// The help text of the setting.
    let description: String
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let entries = try await SettingCatalog.read().settings.map {
        Entry(
          key: $0.key.rawValue,
          value: $0.value,
          description: SettingCatalog.description(of: $0.key)
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIList(items: entries))
      case .plain: CLIOutput.plain(entries.map { [$0.key, String($0.value)] })
      case .human:
        let width = entries.map(\.key.count).max() ?? 0
        for entry in entries {
          let key = entry.key.padding(toLength: width, withPad: " ", startingAt: 0)
          CLIOutput.stdout("\(key)  \(entry.value ? "true " : "false")  \(entry.description)")
        }
      }
    }
  }
}

/// The `ojd setting get` command: prints the value of one setting, the default when none is stored.
struct SettingGetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.setting.get.abstract"),
    discussion: CLILocalized.text(
      "cli.setting.get.discussion"
    )
  )

  /// The setting name.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.group.key"),
      valueName: "key"
    )
  )
  var key: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that `key` names a setting.
  func validate() throws { try SettingCatalog.validate(name: key) }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if key == SettingCatalog.pauseShortcutName {
        try SettingCatalog.printPauseShortcut(SettingCatalog.store.pauseShortcut())
        return
      }
      let setting = try SettingCatalog.key(key)
      let value = try await SettingCatalog.read().value(of: setting) ?? setting.defaultValue
      try SettingResult.print(setting, value: value)
    }
  }
}

/// The `ojd setting set` command: changes one setting through the service.
struct SettingSetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.setting.set.abstract"),
    discussion: CLILocalized.text(
      "platform.macos.cli.setting.set.discussion"
    )
  )

  /// The setting name.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.key"),
      valueName: "key"
    )
  )
  var key: String

  /// The value to store, `true` or `false`.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.value"),
      valueName: "value"
    )
  )
  var value: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that `key` names a setting and that `value` is a value for it.
  func validate() throws {
    if key == SettingCatalog.pauseShortcutName {
      _ = try SettingCatalog.pauseShortcut(value)
    } else {
      _ = try SettingCatalog.value(value, for: SettingCatalog.key(key))
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if key == SettingCatalog.pauseShortcutName {
        let shortcut = try SettingCatalog.pauseShortcut(value)
        try SettingCatalog.store.setPauseShortcut(shortcut)
        try SettingCatalog.printPauseShortcut(shortcut)
        return
      }
      let setting = try SettingCatalog.key(key)
      let requested = try SettingCatalog.value(value, for: setting)
      let applied = try await ServiceConnection.request { client in
        try await client.setSetting(setting, to: requested)
      }.value(of: setting)
      guard applied == requested else {
        throw CLIFailure(
          .systemRequestFailed,
          CLILocalized.format(
            "platform.macos.cli.setting.set.notApplied",
            setting.rawValue,
            setting.rawValue
          )
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(SettingResult(key: setting.rawValue, value: requested))
      case .plain: CLIOutput.plain([[setting.rawValue, String(requested)]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.setting.set.success",
            setting.rawValue,
            String(requested)
          )
        )
      }
    }
  }
}

/// The `ojd setting reset` command: moves `Settings.plist` to the Trash, so every setting returns
/// to its default.
///
/// It works on the file itself, so it also fixes a file the service rejects and needs no running
/// service.
struct SettingResetCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "reset",
    abstract: CLILocalized.text("cli.setting.reset.abstract"),
    discussion: CLILocalized.text("cli.setting.reset.discussion")
  )

  /// The settings file the command moves; tests point it at a temporary folder.
  @TaskLocal
  static var store = SettingsStore()

  /// The `--json` result. `moved` is false when there was no file.
  struct Result: Encodable, Equatable {
    /// The path of the settings file.
    let file: String
    /// Whether the command moved a file.
    let moved: Bool
  }

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let settingsStore = Self.store
      let file = settingsStore.userFileURL.path
      var moved = false
      if FileManager.default.fileExists(atPath: file) {
        try CLITerminal.confirm(CLILocalized.text("cli.setting.reset.confirm"), force: force)
        moved = try settingsStore.moveToTrash()
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: Result(file: file, moved: moved)))
      case .plain: CLIOutput.plain([[file, String(moved)]])
      case .human:
        if moved {
          CLIOutput.success(CLILocalized.format("cli.setting.reset.success", file))
        } else {
          CLIOutput.stdout(CLILocalized.format("cli.setting.reset.none", file))
        }
      }
    }
  }
}

/// The `ojd setting test-notification` command: asks the service to announce a test notification to
/// the app and reports how it ended.
///
/// The app answers with `shown`, `denied` or `failed`; the service answers `noAnswer` when no app
/// took the announcement or reported in time (`TestNotificationDeadlines`). Each other outcome is a
/// named failure: E2037 for denied notifications, E2006 with the system's reason for a failed
/// delivery, and E2036 for no answer. The service holds the request until then, so without
/// `--timeout` the command waits `ServiceTimeouts.testNotification`.
struct SettingTestNotificationCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "test-notification",
    abstract: CLILocalized.text("cli.setting.testNotification.abstract"),
    discussion: CLILocalized.format(
      "cli.setting.testNotification.discussion",
      unsafe String(format: "%g", ServiceTimeouts.testNotification)
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The outcome of the notification.
    let outcome: String
  }

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let outcome = try await ServiceConnection.request(
        timeout: CLIContext.current.timeout ?? ServiceTimeouts.testNotification
      ) { client in
        try await client.sendTestNotification()
      }
      switch outcome {
      case .shown: break
      case .denied:
        throw CLIFailure(.notificationsDenied, CLILocalized.text("error.E2037.message"))
      case .failed(let reason):
        throw CLIFailure.serviceRequestFailed(reason)
      case .noAnswer:
        throw CLIFailure(.noApplicationAnswered, CLILocalized.text("error.E2036.message"))
      }
      switch CLIContext.current.format {
      case .json:
        try CLIOutput.json(CLIStatus(details: Result(outcome: "Shown")))
      case .plain: CLIOutput.plain([["shown"]])
      case .human: CLIOutput.success(CLILocalized.text("cli.setting.testNotification.success"))
      }
    }
  }
}
