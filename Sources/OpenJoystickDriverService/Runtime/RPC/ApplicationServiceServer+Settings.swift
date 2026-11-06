import Foundation
import OpenJoystickDriverKit

/// Reads and changes whether macOS opens the main app at login.
struct LaunchAtLoginControl: Sendable {
  /// Reads whether the login item is on.
  let isEnabled: @Sendable () -> Bool
  /// Turns the login item on or off.
  let setEnabled: @Sendable (Bool) throws -> Void

  /// The macOS login item, recording the choice in `settings`.
  static func system(settings: SettingsStore) -> Self {
    Self(
      isEnabled: { ApplicationServiceManager.isLaunchAtLoginEnabled },
      setEnabled: { enabled in
        if enabled {
          try ApplicationServiceManager.install(settings: settings)
        } else {
          try ApplicationServiceManager.uninstall(settings: settings)
        }
      }
    )
  }
}

extension ApplicationServiceServer {
  /// Every app setting with its current value.
  ///
  /// Throws when a settings file is damaged or has an unsupported `apiVersion`.
  func getSettings() throws -> ApplicationSettingsPayload {
    let stored = try settings.load()
    return ApplicationSettingsPayload(
      settings: ApplicationSettingKey.allCases.map {
        ApplicationSettingValue(key: $0, value: currentValue(of: $0, stored: stored))
      }
    )
  }

  /// Applies one setting and returns every setting as it stands afterward.
  ///
  /// The login item can stay off after a successful change while macOS waits for the user to
  /// approve it, so callers compare the returned value with the one they asked for.
  func setSetting(_ key: ApplicationSettingKey, to value: Bool) throws -> ApplicationSettingsPayload
  {
    if key == .launchAtLogin {
      try launchAtLogin.setEnabled(value)
    } else {
      try settings.set(key, to: value)
    }
    return try getSettings()
  }

  /// The login item reports macOS's state; every other key reports the user settings file.
  private func currentValue(of key: ApplicationSettingKey, stored: SettingsDocument) -> Bool {
    key == .launchAtLogin ? launchAtLogin.isEnabled() : stored[key] ?? key.defaultValue
  }
}
