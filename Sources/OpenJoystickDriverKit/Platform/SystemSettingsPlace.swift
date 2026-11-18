package import Foundation

/// A place in macOS System Settings, or System Preferences on macOS 12, that OJD sends the user to.
///
/// macOS renames these places between releases, so each one resolves to the catalog key of the
/// path the running macOS shows.
package enum SystemSettingsPlace: Sendable, CaseIterable {
  /// Where the user allows the login item.
  case loginItems
  /// Where the user allows Input Monitoring.
  case inputMonitoring
  /// Where the user allows Accessibility, which macOS 27 calls Device Control and Data Access.
  case accessibility
  /// Where the user allows the Xbox USB driver.
  case driverApproval

  /// The catalog key of the name that `version` gives the settings app: System Preferences on
  /// macOS 12, and System Settings on macOS 13 and later, which some languages spell differently
  /// on macOS 13 to 15, 26, and 27.
  package static func appLocalizationKey(
    on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) -> String {
    switch version.majorVersion {
    case ..<13: "platform.macos.term.settingsApp.systemPreferences"
    case 13...15: "platform.macos.term.settingsApp.systemSettingsMacOS13"
    case 16..<27: "platform.macos.term.settingsApp.systemSettingsMacOS26"
    default: "platform.macos.term.settingsApp.systemSettings"
    }
  }

  /// The catalog key of the path that `version` shows.
  ///
  /// macOS 12 lists the permissions under Security & Privacy > Privacy and asks for the driver in
  /// Security & Privacy > General. It has no login item for OJD, because SMAppService needs
  /// macOS 13, so login items resolve to the macOS 13 path. macOS 13 and 14 list login items
  /// under General > Login Items and ask for the driver in Privacy & Security; macOS 15 moves
  /// both under Login Items & Extensions. Some languages spell Input Monitoring differently in
  /// macOS 13, 14, 15 to 26, and 27. macOS 27 renames Accessibility to Device Control and Data
  /// Access.
  package func localizationKey(
    on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) -> String {
    let major = version.majorVersion
    switch self {
    case .loginItems:
      return major >= 15
        ? "platform.macos.term.settingsPlace.loginItemsAndExtensions"
        : "platform.macos.term.settingsPlace.loginItems"
    case .inputMonitoring:
      switch major {
      case ..<13: return "platform.macos.term.settingsPlace.preferencesInputMonitoring"
      case 13: return "platform.macos.term.settingsPlace.inputMonitoringMacOS13"
      case 14: return "platform.macos.term.settingsPlace.inputMonitoringMacOS14"
      case 15..<27: return "platform.macos.term.settingsPlace.inputMonitoringMacOS15"
      default: return "platform.macos.term.settingsPlace.inputMonitoring"
      }
    case .accessibility:
      if major < 13 { return "platform.macos.term.settingsPlace.preferencesAccessibility" }
      return major >= 27
        ? "platform.macos.term.settingsPlace.deviceControl"
        : "platform.macos.term.settingsPlace.accessibility"
    case .driverApproval:
      if major < 13 { return "platform.macos.term.settingsPlace.preferencesGeneral" }
      return major >= 15
        ? "platform.macos.term.settingsPlace.driverExtensions"
        : "platform.macos.term.settingsPlace.securityApproval"
    }
  }
}
