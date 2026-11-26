import ArgumentParser
import Foundation
import OpenJoystickDriverKit

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

  /// The name of the interface level, the other setting that holds text.
  static let interfaceLevelName = "interfaceLevel"

  /// Parses `text` as an interface level.
  ///
  /// - Throws: ``ValidationError`` when `text` is neither `Simple` nor `Advanced`.
  static func interfaceLevel(_ text: String) throws -> InterfaceLevel {
    guard let level = InterfaceLevel(rawValue: text) else {
      throw ValidationError(CLILocalized.format("cli.setting.set.badInterfaceLevel", text))
    }
    return level
  }

  /// Prints `level` as `key` and `value` JSON, or as the text alone.
  static func printInterfaceLevel(_ level: InterfaceLevel) throws {
    switch CLIContext.current.format {
    case .json:
      try CLIOutput.json(PauseShortcutResult(key: interfaceLevelName, value: level.rawValue))
    case .plain, .human: CLIOutput.stdout(level.rawValue)
    }
  }

  /// The name of the idle disconnect time, the setting that holds minutes or `off`.
  static let idleDisconnectName = "idleDisconnectMinutes"

  /// The text that turns the idle disconnect off.
  static let idleDisconnectOff = "off"

  /// Parses `text` as minutes in ``SettingsDocument/idleDisconnectRange``, or `off`.
  ///
  /// - Throws: ``ValidationError`` when `text` is neither.
  static func idleDisconnectMinutes(_ text: String) throws -> Int? {
    guard text != idleDisconnectOff else { return nil }
    guard let minutes = Int(text), SettingsDocument.idleDisconnectRange.contains(minutes) else {
      throw ValidationError(
        CLILocalized.format(
          "cli.setting.set.badIdleDisconnect",
          text,
          String(SettingsDocument.idleDisconnectRange.lowerBound),
          String(SettingsDocument.idleDisconnectRange.upperBound)
        )
      )
    }
    return minutes
  }

  /// Prints `minutes` as `key` and `value` JSON, or as the text alone.
  static func printIdleDisconnect(_ minutes: Int?) throws {
    let text = minutes.map(String.init) ?? idleDisconnectOff
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(PauseShortcutResult(key: idleDisconnectName, value: text))
    case .plain, .human: CLIOutput.stdout(text)
    }
  }

  /// The text that clears the pause shortcut.
  static let noShortcut = "none"

  /// The settings file the pause shortcut is read from and written to; tests point it at a
  /// temporary folder.
  @TaskLocal
  static var store = SettingsStore()

  /// The names of every setting, as shown in help and error text.
  static var keyNames: String {
    (ApplicationSettingKey.allCases.map(\.rawValue) + [
      interfaceLevelName, pauseShortcutName, idleDisconnectName,
    ])
    .joined(separator: ", ")
  }

  /// Checks that `name` names a setting.
  ///
  /// - Throws: ``ValidationError`` when no setting has that name.
  static func validate(name: String) throws {
    if ![pauseShortcutName, interfaceLevelName, idleDisconnectName].contains(name) {
      _ = try key(name)
    }
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
