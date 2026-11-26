import Foundation
import OpenJoystickDriverKit

/// The main menu as data: titles, key equivalents, actions, enabled rules and GUI counterparts.
///
/// The test checks this; ``MainMenuRenderer`` renders it to an `NSMenu`.
enum MainMenuModel {
  /// Every item of every menu in order.
  static var allItems: [MainMenuItem] { sections.flatMap(\.items) }

  /// Returns the first item with the action, or nil when no item has it.
  static func item(for action: MainMenuAction) -> MainMenuItem? {
    allItems.first { $0.action == action }
  }

  /// Returns the item that does what the toolbar item of `action` does.
  static func item(forToolbar action: MainWindowToolbarAction) -> MainMenuItem? {
    item(for: action.menuAction)
  }

  /// Returns whether the item is enabled in the state; an item on the responder chain counts as
  /// enabled, because AppKit validates it.
  static func isEnabled(_ item: MainMenuItem, state: MainMenuState) -> Bool {
    switch item.enabled {
    case .responderChain: return true
    case .requires(let requirements): return requirements.allSatisfy(state.satisfies)
    }
  }

  /// Returns whether the item shows a checkmark: the interface level item of the current level.
  static func isChecked(_ item: MainMenuItem, state: MainMenuState) -> Bool {
    guard case .setInterfaceLevel(let level) = item.action else { return false }
    return level == state.interfaceLevel
  }

  /// The text of the controller target row: the selected controller's name; the key that says no
  /// controller is connected; or, when controllers are connected but none is selected (or the
  /// selected one is gone), the key that says no controller is selected.
  static func controllerTargetTitle(state: MainMenuState) -> StatusItemTitle {
    if let controller = state.controller { return .verbatim(controller.name) }
    if state.controllers.isEmpty { return .key(noControllerTitleKey) }
    return .key("ui.menu.controller.noneSelected")
  }

  /// The disabled row of the Controller menu and the status item's Controllers submenu while no
  /// controller is connected.
  static let noControllerTitleKey = "ui.menu.controller.noneConnected"

  /// The disabled row of the Activate Profile submenu while no profile exists: the submenu stays
  /// openable, so its one row says why it holds no profile.
  static let noProfilesTitleKey = "ui.menu.profile.none"

  /// The disabled row of the Activate Profile submenu while the profile list is loading or the
  /// service cannot report it, so the submenu does not claim that no profile exists.
  static let profilesUnavailableTitleKey = "ui.menu.profile.unavailable"

  /// The one disabled row of an Activate Profile submenu that lists no profile: No Profiles once
  /// the service reported an empty list, Profiles Unavailable while it has not reported one.
  static func emptyActivateProfileTitleKey(profileListRead: Bool) -> String {
    profileListRead ? noProfilesTitleKey : profilesUnavailableTitleKey
  }

  /// The identifier of the menu bar item that opens a section's menu.
  ///
  /// The `menu.` prefix keeps it apart from every item id, which the coordinator looks items up by.
  static func menuBarItemIdentifier(sectionID: String) -> String {
    "menu.\(sectionID)"
  }

  /// The disabled row of the status item's Deactivate submenu while no profile is active.
  static let noActiveProfileTitleKey = "ui.menu.profile.noneActive"

  /// The one disabled row of a Deactivate submenu that lists no profile: No Active Profile once
  /// the service reported the list, Profiles Unavailable while it has not reported one.
  static func emptyDeactivateProfileTitleKey(profileListRead: Bool) -> String {
    profileListRead ? noActiveProfileTitleKey : profilesUnavailableTitleKey
  }

  /// The title key to show: the alternate one for Hide Sidebar, Exit Full Screen and Resume.
  static func titleKey(of item: MainMenuItem, state: MainMenuState) -> String {
    guard let alternate = item.alternateTitleKey else { return item.titleKey }
    switch item.action {
    case .toggleToolbar: return state.isToolbarVisible ? alternate : item.titleKey
    case .toggleSidebar: return state.isSidebarVisible ? alternate : item.titleKey
    case .toggleFullScreen: return state.isFullScreen ? alternate : item.titleKey
    case .suspendOrResumeController:
      return state.controller?.isSuspended == true ? alternate : item.titleKey
    default: return item.titleKey
    }
  }

  /// Returns the localization key of the tooltip of `item` in `state`: the item that resumes a
  /// suspended controller says so.
  static func helpKey(of item: MainMenuItem, state: MainMenuState) -> String {
    if item.action == .suspendOrResumeController, state.controller?.isSuspended == true {
      return "ui.help.resume"
    }
    return item.action.helpKey
  }

}
