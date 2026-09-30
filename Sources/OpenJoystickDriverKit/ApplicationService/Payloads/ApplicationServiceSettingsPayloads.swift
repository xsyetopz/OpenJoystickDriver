import Foundation

/// An app setting the service can read and apply; each raw value is the stable kebab-case name.
public enum ApplicationSettingKey: String, Codable, CaseIterable, Sendable {
  case launchAtLogin = "launch-at-login"
  case notificationSounds = "notification-sounds"
  case includePrereleaseUpdates = "include-prerelease-updates"
  case developerTools = "developer-tools"

  /// The `UserDefaults` key that stores the setting, or nil when macOS stores it.
  public var defaultsKey: String? {
    switch self {
    case .launchAtLogin: nil
    case .notificationSounds: "OpenJoystickDriver.notifications.sounds"
    case .includePrereleaseUpdates: "OpenJoystickDriver.updates.includePrereleases"
    case .developerTools: "OpenJoystickDriver.developerTools.enabled"
    }
  }

  /// The value while nothing has stored one.
  public var defaultValue: Bool { self == .notificationSounds }
}

/// One app setting and its current value.
public struct ApplicationSettingValue: Codable, Equatable, Sendable {
  public let key: ApplicationSettingKey
  public let value: Bool

  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}

/// The result of `getSettings` and `setSetting`: every setting, in `ApplicationSettingKey` order.
public struct ApplicationSettingsPayload: Codable, Equatable, Sendable {
  public let settings: [ApplicationSettingValue]

  public init(settings: [ApplicationSettingValue]) { self.settings = settings }

  public func value(of key: ApplicationSettingKey) -> Bool? {
    settings.first { $0.key == key }?.value
  }
}

/// Arguments of `setSetting`.
public struct ApplicationServiceSettingArguments: Codable, Sendable {
  public let key: ApplicationSettingKey
  public let value: Bool

  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}
