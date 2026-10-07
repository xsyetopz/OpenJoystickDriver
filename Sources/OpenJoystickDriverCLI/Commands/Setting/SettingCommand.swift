import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct SettingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setting",
    abstract: CLILocalized.text(
      "cli.setting.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.setting.discussion"
    ),
    subcommands: [SettingListCommand.self, SettingGetCommand.self, SettingSetCommand.self]
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions
}

/// The settings `ojd setting` names, with their help text and value parsing.
enum SettingCatalog {
  static func description(of key: ApplicationSettingKey) -> String {
    switch key {
    case .launchAtLogin:
      CLILocalized.text("cli.setting.launch_at_login")
    case .notificationSounds:
      CLILocalized.text("cli.setting.notification_sounds")
    case .includePrereleaseUpdates:
      CLILocalized.text(
        "cli.setting.include_prerelease_updates"
      )
    case .developerTools:
      CLILocalized.text(
        "cli.setting.developer_tools"
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
    abstract: CLILocalized.text("cli.setting.list.abstract")
  )

  /// One setting in the `--json` result.
  struct Entry: Encodable, Equatable {
    let key: String
    let value: Bool
    let description: String
  }

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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

struct SettingGetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: CLILocalized.text("cli.setting.get.abstract"),
    discussion: CLILocalized.text(
      "cli.setting.get.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.key"),
      valueName: "key"
    )
  )
  var key: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
    abstract: CLILocalized.text("cli.setting.set.abstract"),
    discussion: CLILocalized.text(
      "cli.setting.set.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.key"),
      valueName: "key"
    )
  )
  var key: String

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.setting.set.value"),
      valueName: "value"
    )
  )
  var value: String

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
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
          .systemRequestFailed,
          CLILocalized.format(
            "cli.setting.set.not_applied",
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
            key.rawValue,
            String(requested)
          )
        )
      }
    }
  }
}
