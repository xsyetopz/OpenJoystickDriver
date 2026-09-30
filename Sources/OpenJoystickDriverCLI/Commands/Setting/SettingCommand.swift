import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct SettingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setting",
    abstract: CLILocalized.text(
      "cli.setting.abstract",
      "List, read, or change OpenJoystickDriver app settings."
    ),
    discussion: CLILocalized.text(
      "cli.setting.discussion",
      "The running service applies each setting, so every setting command needs it."
    ),
    subcommands: [SettingListCommand.self, SettingGetCommand.self, SettingSetCommand.self]
  )

  @OptionGroup
  var global: GlobalOptions
}

/// The settings `ojd setting` names, with their help text and value parsing.
enum SettingCatalog {
  static func description(of key: ApplicationSettingKey) -> String {
    switch key {
    case .launchAtLogin:
      CLILocalized.text("cli.setting.launch_at_login", "Open OpenJoystickDriver when you log in.")
    case .notificationSounds:
      CLILocalized.text("cli.setting.notification_sounds", "Play a sound with notifications.")
    case .includePrereleaseUpdates:
      CLILocalized.text(
        "cli.setting.include_prerelease_updates",
        "Include pre-release versions when checking for updates."
      )
    case .developerTools:
      CLILocalized.text(
        "cli.setting.developer_tools",
        "Show the developer tools in the Settings window."
      )
    }
  }

  static var keyNames: String {
    ApplicationSettingKey.allCases.map(\.rawValue).joined(separator: ", ")
  }

  static func key(_ name: String) throws -> ApplicationSettingKey {
    guard let key = ApplicationSettingKey(rawValue: name) else {
      throw ValidationError(
        CLILocalized.format(
          "cli.setting.unknown_key",
          "Unknown setting '%@'. Use one of: %@.",
          name,
          keyNames
        )
      )
    }
    return key
  }

  /// Every setting is on or off, written `true` or `false`.
  static func value(_ text: String, for key: ApplicationSettingKey) throws -> Bool {
    switch text {
    case "true": return true
    case "false": return false
    default:
      throw ValidationError(
        CLILocalized.format(
          "cli.setting.bad_value",
          "'%@' is not a value for %@. Use true or false.",
          text,
          key.rawValue
        )
      )
    }
  }

  static func read() async throws -> ApplicationSettingsPayload {
    try await ServiceConnection.request { client in try await client.getSettings() }
  }
}

/// The `--json` result of `setting get` and `setting set`.
struct SettingResult: Encodable, Equatable {
  let key: String
  let value: Bool

  static func print(_ key: ApplicationSettingKey, value: Bool) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(Self(key: key.rawValue, value: value))
    case .plain, .human: CLIOutput.stdout(String(value))
    }
  }
}

struct SettingListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: CLILocalized.text("cli.setting.list.abstract", "List every setting and its value.")
  )

  /// One setting in the `--json` result.
  struct Entry: Encodable, Equatable {
    let key: String
    let value: Bool
    let description: String
  }

  struct Result: Encodable, Equatable { let settings: [Entry] }

  @OptionGroup
  var global: GlobalOptions

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
      case .json: try CLIOutput.json(Result(settings: entries))
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

struct SettingGetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.setting.get.abstract", "Print the value of one setting."),
    discussion: CLILocalized.text(
      "cli.setting.get.discussion",
      "Prints true or false alone, for scripts. With --json, prints the key and the value."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.key", "The setting to read, such as launch-at-login."),
      valueName: "key"
    )
  )
  var key: String

  @OptionGroup
  var global: GlobalOptions

  func validate() throws { _ = try SettingCatalog.key(key) }

  func run() async throws {
    try await global.run {
      let key = try SettingCatalog.key(key)
      let value = try await SettingCatalog.read().value(of: key) ?? key.defaultValue
      try SettingResult.print(key, value: value)
    }
  }
}

struct SettingSetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: CLILocalized.text("cli.setting.set.abstract", "Change one setting."),
    discussion: CLILocalized.text(
      "cli.setting.set.discussion",
      "Values are true or false. Exits 1 when macOS leaves launch-at-login off until you "
        + "approve it in System Settings."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.key", "The setting to change, such as launch-at-login."),
      valueName: "key"
    )
  )
  var key: String

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.value", "The new value: true or false."),
      valueName: "value"
    )
  )
  var value: String

  @OptionGroup
  var global: GlobalOptions

  func validate() throws { _ = try SettingCatalog.value(value, for: SettingCatalog.key(key)) }

  func run() async throws {
    try await global.run {
      let key = try SettingCatalog.key(key)
      let requested = try SettingCatalog.value(value, for: key)
      let applied = try await ServiceConnection.request { client in
        try await client.setSetting(key, to: requested)
      }.value(of: key)
      guard applied == requested else {
        throw CLIFailure(
          .failure,
          CLILocalized.format(
            "cli.setting.set.not_applied",
            "macOS did not apply %@. Allow OpenJoystickDriver in System Settings > General > "
              + "Login Items, then run 'ojd setting get %@'.",
            key.rawValue,
            key.rawValue
          )
        )
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(SettingResult(key: key.rawValue, value: requested))
      case .plain: CLIOutput.plain([[key.rawValue, String(requested)]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.setting.set.success",
            "Set %@ to %@.",
            key.rawValue,
            String(requested)
          )
        )
      }
    }
  }
}
