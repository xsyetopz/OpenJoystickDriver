import Foundation
import OpenJoystickDriverKit

/// Reads and changes whether macOS opens the main app at login.
struct LaunchAtLoginControl: Sendable {
  let isEnabled: @Sendable () -> Bool
  let setEnabled: @Sendable (Bool) throws -> Void

  static let system = Self(
    isEnabled: { ApplicationServiceManager.isLaunchAtLoginEnabled },
    setEnabled: { enabled in
      if enabled {
        try ApplicationServiceManager.install()
      } else {
        try ApplicationServiceManager.uninstall()
      }
    }
  )
}

extension ApplicationServiceServer {
  /// Every app setting with its current value.
  func getSettings() -> ApplicationSettingsPayload {
    ApplicationSettingsPayload(
      settings: ApplicationSettingKey.allCases.map {
        ApplicationSettingValue(key: $0, value: currentValue(of: $0))
      }
    )
  }

  /// Applies one setting and returns every setting as it stands afterward.
  ///
  /// The login item can stay off after a successful change while macOS waits for the user to
  /// approve it, so callers compare the returned value with the one they asked for.
  func setSetting(_ key: ApplicationSettingKey, to value: Bool) throws -> ApplicationSettingsPayload
  {
    if let defaultsKey = key.defaultsKey {
      defaults.set(value, forKey: defaultsKey)
    } else {
      try launchAtLogin.setEnabled(value)
    }
    return getSettings()
  }

  private func currentValue(of key: ApplicationSettingKey) -> Bool {
    guard let defaultsKey = key.defaultsKey else { return launchAtLogin.isEnabled() }
    return defaults.object(forKey: defaultsKey) as? Bool ?? key.defaultValue
  }
}
