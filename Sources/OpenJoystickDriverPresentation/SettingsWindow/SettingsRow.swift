/// The rows of the Settings window, with the audit IDs P01 to P16.
enum SettingsRow: InterfaceRow {
  /// P01: the Interface pop-up, which shows at both levels so a user can switch back.
  case interfacePicker
  /// P02: Start at login.
  case startAtLogin
  /// P03: Show in menu bar.
  case showInMenuBar
  /// P04: Show in Dock.
  case showInDock
  /// P05: the version and Check Now.
  case version
  /// P06: Check for updates automatically.
  case checkUpdatesAutomatically
  /// P07: Include prerelease updates.
  case prereleaseUpdates
  /// P08: Controller connected and disconnected.
  case controllerNotifications
  /// P09: Profile activated and deactivated.
  case profileNotifications
  /// P10: Play a sound.
  case notificationSound
  /// P11: the notification permission row.
  case notificationPermission
  /// P12: Install Command-Line Tool.
  case commandLineTool
  /// P13: the Xbox USB driver.
  case driverExtension
  /// P14: the Enable Developer Tools switch.
  case developerToolsSwitch
  /// P15: the developer tools.
  case developerTools
  /// P16: the settings error section.
  case errorSection

  var auditIDs: [String] {
    switch self {
    case .interfacePicker: return ["P01"]
    case .startAtLogin: return ["P02"]
    case .showInMenuBar: return ["P03"]
    case .showInDock: return ["P04"]
    case .version: return ["P05"]
    case .checkUpdatesAutomatically: return ["P06"]
    case .prereleaseUpdates: return ["P07"]
    case .controllerNotifications: return ["P08"]
    case .profileNotifications: return ["P09"]
    case .notificationSound: return ["P10"]
    case .notificationPermission: return ["P11"]
    case .commandLineTool: return ["P12"]
    case .driverExtension: return ["P13"]
    case .developerToolsSwitch: return ["P14"]
    case .developerTools: return ["P15"]
    case .errorSection: return ["P16"]
    }
  }

  var rowLevel: InterfaceRowLevel {
    switch self {
    case .commandLineTool, .developerToolsSwitch: return .advanced
    case .developerTools: return .developer
    case .interfacePicker, .startAtLogin, .showInMenuBar, .showInDock, .version,
      .checkUpdatesAutomatically, .prereleaseUpdates, .controllerNotifications,
      .profileNotifications, .notificationSound, .notificationPermission, .driverExtension,
      .errorSection:
      return .simple
    }
  }
}
