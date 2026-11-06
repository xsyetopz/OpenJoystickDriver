import Foundation

/// An app setting the service can read and apply; each raw value is the stable key that
/// `ojd setting` takes and that names the setting in `Settings.json`.
public enum ApplicationSettingKey: String, Codable, CaseIterable, Sendable {
  /// Open OJD at login.
  case launchAtLogin
  /// Show the OJD item in the menu bar.
  case showInMenuBar
  /// Show OJD in the Dock.
  case showInDock
  /// Notify when a controller connects.
  case notifyControllerConnected = "notify.controllerConnected"
  /// Notify when a controller disconnects.
  case notifyControllerDisconnected = "notify.controllerDisconnected"
  /// Notify when a remapping profile is activated.
  case notifyProfileActivated = "notify.profileActivated"
  /// Notify when a remapping profile is deactivated.
  case notifyProfileDeactivated = "notify.profileDeactivated"
  /// Play sounds with notifications.
  case notifySounds = "notify.sounds"
  /// Check for updates automatically.
  case updatesCheckAutomatically = "updates.checkAutomatically"
  /// Offer prerelease versions as updates.
  case updatesIncludePrereleases = "updates.includePrereleases"
  /// Show the developer tools.
  case developerTools

  /// The value while no settings file stores one: true for `showInMenuBar` and `notify.sounds`,
  /// false otherwise (`showInDock` included).
  public var defaultValue: Bool { self == .showInMenuBar || self == .notifySounds }
}

/// One app setting and its current value.
public struct ApplicationSettingValue: Codable, Equatable, Sendable {
  /// The setting.
  public let key: ApplicationSettingKey
  /// Whether the setting is on.
  public let value: Bool

  /// Creates a setting value from its values.
  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}

/// The result of `getSettings` and `setSetting`: every setting, in `ApplicationSettingKey` order.
public struct ApplicationSettingsPayload: Codable, Equatable, Sendable {
  /// Every setting with its value.
  public let settings: [ApplicationSettingValue]

  /// Creates the payload from `settings`.
  public init(settings: [ApplicationSettingValue]) { self.settings = settings }

  /// The value of `key`; nil when the payload does not list it.
  public func value(of key: ApplicationSettingKey) -> Bool? {
    settings.first { $0.key == key }?.value
  }
}

/// Arguments of `setSetting`.
public struct ApplicationServiceSettingArguments: Codable, Sendable {
  /// The setting to change.
  public let key: ApplicationSettingKey
  /// The value to apply.
  public let value: Bool

  /// Creates the arguments from a setting and its value.
  public init(key: ApplicationSettingKey, value: Bool) {
    self.key = key
    self.value = value
  }
}
