import Foundation

/// The contents of one `Settings.plist` layer; every setting is optional, and a setting a layer
/// leaves out falls through to the layer below it.
///
/// See `Resources/Schemas/settings.schema.json`.
public struct SettingsDocument: Equatable, Sendable {
  /// The `kind` of the file.
  public static let kind = "Settings"

  /// Which events post a notification.
  public struct Notify: Equatable, Sendable {
    /// Whether a connected controller posts a notification.
    public var controllerConnected: Bool?
    /// Whether a disconnected controller posts a notification.
    public var controllerDisconnected: Bool?
    /// Whether an activated profile posts a notification.
    public var profileActivated: Bool?
    /// Whether a deactivated profile posts a notification.
    public var profileDeactivated: Bool?
    /// Whether notifications play sounds.
    public var sounds: Bool?

    /// Creates a layer that leaves every notification setting out.
    public init() {}
  }

  /// How update checks behave.
  public struct Updates: Equatable, Sendable {
    /// Whether the app checks for updates by itself.
    public var checkAutomatically: Bool?
    /// Whether update checks offer prereleases.
    public var includePrereleases: Bool?

    /// Creates a layer that leaves every update setting out.
    public init() {}
  }

  /// Internal state, not a setting: true after the user turned launch at login off through the app
  /// or `ojd setting`, so the app does not register itself on its next start.
  ///
  /// The public key `launchAtLogin` is read from and written to the macOS login item, which stays
  /// the source of truth; a change made in System Settings does not update this field.
  public var launchAtLoginOptOut: Bool?
  /// Whether the app shows an item in the menu bar.
  public var showInMenuBar: Bool?
  /// Whether the app shows an icon in the Dock.
  public var showInDock: Bool?
  /// Which events post a notification.
  public var notify = Notify()
  /// How update checks behave.
  public var updates = Updates()
  /// Whether the Settings window shows the developer tools.
  public var developerTools: Bool?

  /// Creates a layer that leaves every setting out.
  public init() {}

  /// Whether this document, with its defaults filled in, turns off both Show in menu bar and
  /// Show in Dock, which would leave the app no visible entry point.
  public var hasNoVisibleEntryPoint: Bool {
    let menuBar = showInMenuBar ?? ApplicationSettingKey.showInMenuBar.defaultValue
    let dock = showInDock ?? ApplicationSettingKey.showInDock.defaultValue
    return !menuBar && !dock
  }

  /// The stored value of `key`, or nil when this layer leaves it out.
  ///
  /// `launchAtLogin` here is the opposite of the stored `launchAtLoginOptOut`; it is not the
  /// state of the login item, which only macOS knows.
  public subscript(key: ApplicationSettingKey) -> Bool? {
    get {
      switch key {
      case .launchAtLogin: launchAtLoginOptOut.map { !$0 }
      case .showInMenuBar: showInMenuBar
      case .showInDock: showInDock
      case .notifyControllerConnected: notify.controllerConnected
      case .notifyControllerDisconnected: notify.controllerDisconnected
      case .notifyProfileActivated: notify.profileActivated
      case .notifyProfileDeactivated: notify.profileDeactivated
      case .notifySounds: notify.sounds
      case .updatesCheckAutomatically: updates.checkAutomatically
      case .updatesIncludePrereleases: updates.includePrereleases
      case .developerTools: developerTools
      }
    }
    set {
      switch key {
      case .launchAtLogin: launchAtLoginOptOut = newValue.map { !$0 }
      case .showInMenuBar: showInMenuBar = newValue
      case .showInDock: showInDock = newValue
      case .notifyControllerConnected: notify.controllerConnected = newValue
      case .notifyControllerDisconnected: notify.controllerDisconnected = newValue
      case .notifyProfileActivated: notify.profileActivated = newValue
      case .notifyProfileDeactivated: notify.profileDeactivated = newValue
      case .notifySounds: notify.sounds = newValue
      case .updatesCheckAutomatically: updates.checkAutomatically = newValue
      case .updatesIncludePrereleases: updates.includePrereleases = newValue
      case .developerTools: developerTools = newValue
      }
    }
  }

  /// This layer with every setting that `upper` stores replacing the one here.
  public func overlaid(by upper: Self) -> Self {
    var merged = self
    for key in ApplicationSettingKey.allCases {
      if let value = upper[key] { merged[key] = value }
    }
    return merged
  }
}

/// A header that is not the supported `apiVersion` and `kind`; the store names the file.
struct SettingsHeaderProblem: Error, Equatable, Sendable {
  /// The problem of the header.
  let problem: DocumentHeaderProblem
}

extension SettingsDocument.Notify: Codable {
  /// The keys of the notification settings.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The settings that post a notification.
    case controllerConnected, controllerDisconnected, profileActivated, profileDeactivated, sounds
  }

  /// Decodes the notification settings; a key that the schema does not name is refused.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    controllerConnected = try container.decodeIfPresent(Bool.self, forKey: .controllerConnected)
    controllerDisconnected = try container.decodeIfPresent(
      Bool.self,
      forKey: .controllerDisconnected
    )
    profileActivated = try container.decodeIfPresent(Bool.self, forKey: .profileActivated)
    profileDeactivated = try container.decodeIfPresent(Bool.self, forKey: .profileDeactivated)
    sounds = try container.decodeIfPresent(Bool.self, forKey: .sounds)
  }

  /// Encodes the notification settings that are set.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(controllerConnected, forKey: .controllerConnected)
    try container.encodeIfPresent(controllerDisconnected, forKey: .controllerDisconnected)
    try container.encodeIfPresent(profileActivated, forKey: .profileActivated)
    try container.encodeIfPresent(profileDeactivated, forKey: .profileDeactivated)
    try container.encodeIfPresent(sounds, forKey: .sounds)
  }
}

extension SettingsDocument.Updates: Codable {
  /// The keys of the update settings.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The update settings.
    case checkAutomatically, includePrereleases
  }

  /// Decodes the update settings; a key that the schema does not name is refused.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    checkAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checkAutomatically)
    includePrereleases = try container.decodeIfPresent(Bool.self, forKey: .includePrereleases)
  }

  /// Encodes the update settings that are set.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(checkAutomatically, forKey: .checkAutomatically)
    try container.encodeIfPresent(includePrereleases, forKey: .includePrereleases)
  }
}

extension SettingsDocument: Codable {
  /// The keys of a settings document.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The header, the settings and their groups.
    case apiVersion, kind, launchAtLoginOptOut, showInMenuBar, showInDock, notify, updates,
      developerTools
  }

  /// Decodes a settings layer; a key that the schema does not name is refused.
  ///
  /// - Throws: `SettingsHeaderProblem` when `apiVersion` or `kind` is not the supported one.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      throw SettingsHeaderProblem(problem: problem)
    }
    try decoder.rejectUnknownKeys(CodingKeys.self)
    launchAtLoginOptOut = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginOptOut)
    showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar)
    showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock)
    notify = try container.decodeIfPresent(Notify.self, forKey: .notify) ?? Notify()
    updates = try container.decodeIfPresent(Updates.self, forKey: .updates) ?? Updates()
    developerTools = try container.decodeIfPresent(Bool.self, forKey: .developerTools)
  }

  /// Encodes the header and the settings that are set.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encodeIfPresent(launchAtLoginOptOut, forKey: .launchAtLoginOptOut)
    try container.encodeIfPresent(showInMenuBar, forKey: .showInMenuBar)
    try container.encodeIfPresent(showInDock, forKey: .showInDock)
    if notify != Notify() { try container.encode(notify, forKey: .notify) }
    if updates != Updates() { try container.encode(updates, forKey: .updates) }
    try container.encodeIfPresent(developerTools, forKey: .developerTools)
  }
}
