import Foundation

/// The five areas of the main window, in sidebar order.
///
/// `Command-1` to `Command-5` select them in this order.
public enum MainWindowArea: String, CaseIterable, Identifiable, Hashable, Sendable {
  /// The Controllers area.
  case controllers
  /// The Profiles area.
  case profiles
  /// The Library area.
  case library
  /// The Access area.
  case access
  /// The Activity area.
  case activity

  /// The raw value, which identifies the area.
  public var id: String { rawValue }

  /// The digit that selects this area with `Command`.
  public var keyEquivalent: String {
    switch self {
    case .controllers: return "1"
    case .profiles: return "2"
    case .library: return "3"
    case .access: return "4"
    case .activity: return "5"
    }
  }

  /// The name of the wiki page, without `.md`, that explains this area.
  public var wikiPage: String {
    switch self {
    case .controllers: return "Connecting-Controllers"
    case .profiles: return "Remapping-Profiles"
    case .library: return "Controller-Records"
    case .access: return "Permissions-and-Security"
    case .activity: return "Troubleshooting"
    }
  }

  /// The address of this area's page on the project's GitHub wiki.
  var wikiURL: URL {
    URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/wiki/\(wikiPage)")
      ?? URL(fileURLWithPath: "/")
  }

  /// The SF Symbol of the area's sidebar row, shown before its title.
  public var symbolName: String {
    switch self {
    case .controllers: return "gamecontroller"
    case .profiles: return "slider.horizontal.3"
    case .library: return "books.vertical"
    case .access: return "lock.shield"
    case .activity: return "list.bullet.rectangle"
    }
  }

  /// The localization key of the area's title: its sidebar row, its View menu item and the window
  /// title while it is selected.
  public var titleKey: String { "ui.sidebar.\(rawValue).title" }

  /// Whether the area shows a content list column between the sidebar and its detail.
  public var hasListColumn: Bool {
    switch self {
    case .controllers, .profiles, .library: return true
    case .access, .activity: return false
    }
  }
}

/// The half of a list and detail area that a view renders.
enum MainWindowColumn {
  /// The content list column.
  case list
  /// The detail column.
  case detail
}

/// Opens the main window on an area.
///
/// The status item, the main menu and other windows reach the main window only through this.
@preconcurrency
@MainActor
public protocol MainWindowPresenting: AnyObject {
  /// Shows the main window on `area`, or on the area it already shows when nil.
  func showMainWindow(area: MainWindowArea?)
  /// Shows the Explain Error Code sheet over the main window, in the area it is in.
  func showErrorCodeExplainer()
  /// Opens Controllers with the controller selected, for "Show in Window".
  func showController(id: String)
  /// The session token of the controller selected in the Controllers area, if one is connected.
  var selectedControllerID: String? { get }
  /// The area the main window shows.
  var selectedArea: MainWindowArea { get }
  /// Opens Controllers > Input Test for the controller; false when the controller is not there.
  func showInputTest(controllerID: String) -> Bool
  /// Opens Profiles, asks for a profile file and imports it through the editor's checks.
  func importProfile()
  /// Whether a profile of the library is selected in the Profiles screen.
  var hasSelectedProfile: Bool { get }
  /// Opens Profiles, asks where to save the selected profile and writes it.
  func exportProfile()
  /// Opens Library, asks for a record file or mod folder and shows its install confirmation.
  func installRecordOrMod()
}

/// The panes of the Settings window, in toolbar order.
public enum SettingsWindowPane: String, CaseIterable, Identifiable, Hashable, Sendable {
  /// The General pane.
  case general
  /// The Notifications pane.
  case notifications
  /// The Advanced pane.
  case advanced

  /// The raw value, which identifies the pane.
  public var id: String { rawValue }
  /// The localization key of the pane's title.
  public var titleKey: String { "ui.settings.\(rawValue).title" }
}

/// Opens the Settings window on a pane.
///
/// The status item and the main menu reach it only through this.
@preconcurrency
@MainActor
public protocol SettingsWindowPresenting: AnyObject {
  /// Shows the Settings window on `pane`, or on the pane it already shows when nil.
  func showSettings(pane: SettingsWindowPane?)
}
