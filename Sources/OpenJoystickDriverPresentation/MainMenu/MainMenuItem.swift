import Foundation
import OpenJoystickDriverKit

/// Modifier keys of a menu key equivalent, independent of AppKit.
struct MainMenuModifiers: OptionSet, Hashable, Sendable {
  /// The bits of the modifier keys that are set.
  let rawValue: UInt8

  /// The Command key.
  static let command = Self(rawValue: 1 << 0)
  /// The Shift key.
  static let shift = Self(rawValue: 1 << 1)
  /// The Option key.
  static let option = Self(rawValue: 1 << 2)
  /// The Control key.
  static let control = Self(rawValue: 1 << 3)
}

/// What choosing a main menu item does.
///
/// The renderer maps each case to a responder-chain selector or to the coordinator; the compiler
/// checks the mapping is exhaustive.
enum MainMenuAction: Hashable, Sendable {
  /// Show the About panel.
  case about
  /// Show the Settings window.
  case settings
  /// Open the Services submenu.
  case services
  /// Hide the app.
  case hide
  /// Hide the other apps.
  case hideOthers
  /// Show all apps.
  case showAll
  /// Quit the app.
  case quit

  /// Import a profile from a file.
  case importProfile
  /// Export the selected profile to a file.
  case exportProfile
  /// Install a record or mod.
  case installRecordOrMod
  /// Close the key window.
  case close
  /// Save the support report to a file.
  case saveSupportReport
  /// Save the logs to a file.
  case saveActivityLog

  /// Undo the last edit.
  case undo
  /// Redo the last undone edit.
  case redo
  /// Cut the selection.
  case cut
  /// Copy the selection.
  case copy
  /// Paste from the pasteboard.
  case paste
  /// Delete the selection.
  case delete
  /// Select everything.
  case selectAll
  /// Focus the search field of the list in view.
  case find

  /// Do what the toolbar item of the action does.
  case toolbar(MainWindowToolbarAction)

  /// Show an area of the main window.
  case showArea(MainWindowArea)
  /// Show or hide the toolbar.
  case toggleToolbar
  /// Show or hide the sidebar.
  case toggleSidebar
  /// Enter or exit full screen.
  case toggleFullScreen
  /// Set how much of the interface shows.
  case setInterfaceLevel(InterfaceLevel)

  /// A disabled row that names the controller the menu acts on, or says there is none.
  case controllerTarget
  /// Suspend the selected controller, or resume it while it is suspended.
  case suspendOrResumeController
  /// Open the Input Test for the selected controller.
  case testInput
  /// Disconnect the wireless link of the selected controller.
  case disconnectWirelessLink
  /// Show the selected controller in the main window.
  case showControllerInWindow

  /// Open the submenu of the profiles to activate.
  case activateProfile
  /// Deactivate the active profile of the selected controller.
  case deactivateProfile

  /// Minimize the key window.
  case minimize
  /// Zoom the key window.
  case zoom
  /// Bring all windows of the app to the front.
  case bringAllToFront

  /// Show the Activity area.
  case showActivityLog
  /// Open the Explain Error Code sheet.
  case explainErrorCode
  /// Copy the support report.
  case copySupportReport
  /// Open the wiki page of the main-window area in view.
  case openAreaHelp
  /// Open the page to report a problem.
  case reportProblem
  /// Open the project page in the default browser.
  case openProjectWebsite
}

extension MainMenuAction {
  /// Whether the action runs a flow of its own (a file panel, a profile choice) instead of
  /// only showing an area.
  var performsFlow: Bool {
    switch self {
    case .importProfile, .exportProfile, .activateProfile, .installRecordOrMod: return true
    default: return false
    }
  }
}

/// A condition on the app state that must hold for an item to be enabled.
enum MainMenuRequirement: Hashable, Sendable {
  /// The main window exists.
  case mainWindow
  /// The Settings window exists.
  case settingsWindow
  /// A controller is selected in the Controllers area, so the Controller and Profile menus have
  /// a target.
  case controller
  /// The target controller connects wirelessly.
  case wirelessController
  /// The target controller has an active profile.
  case controllerHasActiveProfile
  /// A profile is selected in the Profiles screen.
  case profileSelected
  /// The toolbar item of the action is shown and enabled.
  case toolbarAction(MainWindowToolbarAction)
  /// The toolbar item of the action is not shown disabled: the command works from any area, and
  /// waits only while the area that shows the item has it disabled.
  case toolbarActionNotDisabled(MainWindowToolbarAction)
  /// The list in view has a search field that shows.
  case searchFieldInView
  /// Never holds; keeps an informational item disabled.
  case unavailable
}

/// How an item decides whether it is enabled.
enum MainMenuEnabledRule: Hashable, Sendable {
  /// AppKit validates the item against the responder chain.
  case responderChain
  /// The item is enabled when every requirement holds.
  case requires(Set<MainMenuRequirement>)

  /// The item is always enabled.
  static let always = Self.requires([])
  /// The item only shows information and is never enabled.
  static let never = Self.requires([.unavailable])
}

/// The place in the GUI that offers the same function as a menu item.
///
/// The menu bar is a subset of the GUI, so every item has one.
enum MainMenuGUICounterpart: Hashable, Sendable {
  /// An area of the main window.
  case area(MainWindowArea)
  /// A pane of the Settings window.
  case settingsPane(SettingsWindowPane)
  /// The sidebar button in the main window toolbar.
  case sidebarToolbarButton
  /// A standard window control or a system-wide macOS command.
  case standardCommand
  /// A link that opens in the default browser.
  case externalLink
}

/// One item of a menu: its title, key equivalent, action, enabled rule and GUI counterpart.
struct MainMenuItem: Equatable, Sendable {
  /// The identifier that the coordinator looks the item up by.
  let id: String
  /// The localization key of the title.
  let titleKey: String
  /// Localization key of the title while the item's alternate state holds; see
  /// ``MainMenuModel/titleKey(of:state:)``.
  let alternateTitleKey: String?
  /// The key of the shortcut, or empty for none.
  let keyEquivalent: String
  /// The modifier keys of the shortcut.
  let modifiers: MainMenuModifiers
  /// What choosing the item does.
  let action: MainMenuAction
  /// How the item decides whether it is enabled.
  let enabled: MainMenuEnabledRule
  /// Where the GUI offers the same function.
  let guiCounterpart: MainMenuGUICounterpart
}

/// A row of a menu: an item or a separator.
enum MainMenuEntry: Equatable, Sendable {
  /// A menu item.
  case item(MainMenuItem)
  /// A separator line.
  case separator

  /// The item of an item row, or nil for a separator.
  var item: MainMenuItem? {
    if case .item(let item) = self { return item }
    return nil
  }
}

/// A menu of the menu bar with its rows.
struct MainMenuSection: Equatable, Sendable {
  /// The identifier of the menu.
  let id: String
  /// The localization key of the menu title.
  let titleKey: String
  /// The rows in order.
  let entries: [MainMenuEntry]

  /// The items of the rows, without the separators.
  var items: [MainMenuItem] { entries.compactMap(\.item) }
}

/// What the menu needs to know about one connected controller.
struct MainMenuControllerState: Equatable, Sendable {
  /// The session token of the controller.
  let id: String
  /// The display name of the controller.
  let name: String
  /// Whether the controller is suspended.
  let isSuspended: Bool
  /// Whether the controller connects wirelessly.
  let isWireless: Bool
  /// Whether a profile is active on the controller.
  let hasActiveProfile: Bool
}

/// The app state that enables items and picks their titles.
struct MainMenuState: Equatable, Sendable {
  /// The connected controllers.
  var controllers: [MainMenuControllerState] = []
  /// The session token of the controller selected in the Controllers area.
  var selectedControllerID: String?
  /// Whether a profile is selected in the Profiles area.
  var hasSelectedProfile = false
  /// Whether the main window exists.
  var hasMainWindow = false
  /// The toolbar actions that are shown and enabled.
  var enabledToolbarActions: Set<MainWindowToolbarAction> = []
  /// The toolbar actions that are shown and disabled.
  var disabledToolbarActions: Set<MainWindowToolbarAction> = []
  /// Whether the list in view has a search field that shows.
  var hasSearchFieldInView = false
  /// Whether the Settings window exists.
  var hasSettingsWindow = false
  /// Whether the main window is full screen.
  var isFullScreen = false
  /// Whether the toolbar shows.
  var isToolbarVisible = false
  /// Whether the sidebar shows.
  var isSidebarVisible = true
  /// How much of the interface shows; the View menu checks the matching item.
  var interfaceLevel = InterfaceLevel.default

  /// The controller the Controller and Profile menus act on: the one selected in the Controllers
  /// area.
  ///
  /// Without a target those items stay disabled and the Controller menu's first row says whether no
  /// controller is connected or none is selected.
  var controller: MainMenuControllerState? {
    guard let selectedControllerID else { return nil }
    return controllers.first { $0.id == selectedControllerID }
  }

  /// Returns whether the state meets the requirement.
  func satisfies(_ requirement: MainMenuRequirement) -> Bool {
    switch requirement {
    case .mainWindow: return hasMainWindow
    case .settingsWindow: return hasSettingsWindow
    case .controller: return controller != nil
    case .wirelessController: return controller?.isWireless == true
    case .controllerHasActiveProfile: return controller?.hasActiveProfile == true
    case .profileSelected: return hasSelectedProfile
    case .toolbarAction(let action): return enabledToolbarActions.contains(action)
    case .toolbarActionNotDisabled(let action): return !disabledToolbarActions.contains(action)
    case .searchFieldInView: return hasSearchFieldInView
    case .unavailable: return false
    }
  }
}
