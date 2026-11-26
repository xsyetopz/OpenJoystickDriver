import Foundation
import OpenJoystickDriverKit

extension MainMenuModel {
  /// The menus of the menu bar in order: the app menu, File, Edit, View, Controller, Profile,
  /// Window and Help.
  static let sections: [MainMenuSection] = [
    appSection, fileSection, editSection, viewSection, controllerSection, profileSection,
    windowSection, helpSection,
  ]

  /// Returns the entry of an item.
  ///
  /// The modifiers apply only when `key` is not empty.
  private static func entry(
    _ id: String,
    _ titleKey: String,
    alternate: String? = nil,
    key: String = "",
    modifiers: MainMenuModifiers = [.command],
    action: MainMenuAction,
    enabled: MainMenuEnabledRule = .always,
    gui: MainMenuGUICounterpart
  ) -> MainMenuEntry {
    .item(
      MainMenuItem(
        id: id,
        titleKey: titleKey,
        alternateTitleKey: alternate,
        keyEquivalent: key,
        modifiers: key.isEmpty ? [] : modifiers,
        action: action,
        enabled: enabled,
        guiCounterpart: gui
      )
    )
  }

  /// Returns the entry of the command that carries a toolbar action: the toolbar item's title,
  /// enabled while the toolbar item is shown and enabled.
  private static func toolbarEntry(_ action: MainWindowToolbarAction) -> MainMenuEntry {
    entry(
      "toolbar.\(action.rawValue)",
      action.labelKey,
      action: .toolbar(action),
      enabled: .requires([.mainWindow, .toolbarAction(action)]),
      gui: .area(action.area)
    )
  }

  /// The rule of the items that need the main window.
  private static let needsMainWindow = MainMenuEnabledRule.requires([.mainWindow])

  /// The app menu: About, Settings, Services, Hide, Hide Others, Show All and Quit.
  private static let appSection = MainMenuSection(
    id: "app",
    titleKey: "term.app.name",
    entries: [
      entry("about", "ui.menu.app.about", action: .about, gui: .standardCommand),
      .separator,
      entry(
        "settings",
        "ui.menu.app.settings",
        key: ",",
        action: .settings,
        enabled: .requires([.settingsWindow]),
        gui: .settingsPane(.general)
      ),
      .separator,
      entry(
        "services",
        "ui.menu.app.services",
        action: .services,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "hide",
        "ui.menu.app.hide",
        key: "h",
        action: .hide,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "hideOthers",
        "ui.menu.app.hideOthers",
        key: "h",
        modifiers: [.command, .option],
        action: .hideOthers,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "showAll",
        "ui.menu.app.showAll",
        action: .showAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry("quit", "ui.menu.app.quit", key: "q", action: .quit, gui: .standardCommand),
    ]
  )

  /// The File menu: importing and exporting profiles, installing a record or mod, the Library and
  /// Access commands of the toolbar, closing the window, and saving the support report and the
  /// activity log.
  private static let fileSection = MainMenuSection(
    id: "file",
    titleKey: "ui.menu.file.title",
    entries: [
      entry(
        "importProfile",
        "ui.menu.file.importProfile",
        key: "o",
        action: .importProfile,
        enabled: .requires([.mainWindow, .toolbarActionNotDisabled(.importProfile)]),
        gui: .area(.profiles)
      ),
      entry(
        "installRecordOrMod",
        "ui.menu.file.installRecordOrMod",
        action: .installRecordOrMod,
        enabled: .requires([.mainWindow, .toolbarActionNotDisabled(.installLibraryItem)]),
        gui: .area(.library)
      ),
      .separator,
      toolbarEntry(.validateLibraryItem),
      toolbarEntry(.testLibraryRecord),
      toolbarEntry(.removeLibraryItem),
      .separator,
      toolbarEntry(.grantProgram),
      toolbarEntry(.createToken),
      .separator,
      entry(
        "close",
        "ui.menu.file.close",
        key: "w",
        action: .close,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "exportProfile",
        "ui.menu.file.exportProfile",
        action: .exportProfile,
        enabled: .requires([
          .mainWindow, .profileSelected, .toolbarActionNotDisabled(.exportProfile),
        ]),
        gui: .area(.profiles)
      ),
      entry(
        "saveSupportReport",
        "ui.menu.file.saveSupportReport",
        action: .saveSupportReport,
        gui: .area(.activity)
      ),
      entry(
        "saveActivityLog",
        "ui.menu.file.saveActivityLog",
        action: .saveActivityLog,
        enabled: .requires([.toolbarActionNotDisabled(.saveActivityLog)]),
        gui: .area(.activity)
      ),
      toolbarEntry(.showActivityLogInFinder),
    ]
  )

  /// The Edit menu: Undo, Redo, Cut, Copy, Copy Activity Log, Paste, Delete, Select All and Find.
  private static let editSection = MainMenuSection(
    id: "edit",
    titleKey: "ui.menu.edit.title",
    entries: [
      entry(
        "undo",
        "ui.menu.edit.undo",
        key: "z",
        action: .undo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "redo",
        "ui.menu.edit.redo",
        key: "z",
        modifiers: [.command, .shift],
        action: .redo,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "cut",
        "ui.menu.edit.cut",
        key: "x",
        action: .cut,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "copy",
        "ui.menu.edit.copy",
        key: "c",
        action: .copy,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      toolbarEntry(.copyActivityLog),
      entry(
        "paste",
        "ui.menu.edit.paste",
        key: "v",
        action: .paste,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "delete",
        "action.delete",
        action: .delete,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "selectAll",
        "ui.menu.edit.selectAll",
        key: "a",
        action: .selectAll,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "find",
        "ui.menu.edit.find",
        key: "f",
        action: .find,
        enabled: .requires([.mainWindow, .searchFieldInView]),
        gui: .standardCommand
      ),
    ]
  )

  /// The View menu: one item for each area of the main window, then the Activity commands of the
  /// toolbar, then the toolbar, sidebar and full screen items.
  private static let viewSection = MainMenuSection(
    id: "view",
    titleKey: "ui.menu.view.title",
    entries: MainWindowArea.allCases.map { area in
      entry(
        "showArea.\(area.rawValue)",
        area.titleKey,
        key: area.keyEquivalent,
        action: .showArea(area),
        enabled: needsMainWindow,
        gui: .area(area)
      )
    } + [
      .separator,
      entry(
        "interfaceLevel.simple",
        "ui.menu.view.interfaceSimple",
        action: .setInterfaceLevel(.simple),
        gui: .settingsPane(.general)
      ),
      entry(
        "interfaceLevel.advanced",
        "ui.menu.view.interfaceAdvanced",
        action: .setInterfaceLevel(.advanced),
        gui: .settingsPane(.general)
      ),
      .separator,
      toolbarEntry(.activityMode),
      toolbarEntry(.activityFilter),
      toolbarEntry(.runDiagnostics),
      .separator,
      entry(
        "toggleToolbar",
        "ui.menu.view.showToolbar",
        alternate: "ui.menu.view.hideToolbar",
        key: "t",
        modifiers: [.command, .option],
        action: .toggleToolbar,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "toggleSidebar",
        "ui.menu.view.showSidebar",
        alternate: "ui.menu.view.hideSidebar",
        key: "s",
        modifiers: [.command, .control],
        action: .toggleSidebar,
        enabled: .responderChain,
        gui: .sidebarToolbarButton
      ),
      .separator,
      entry(
        "toggleFullScreen",
        "ui.menu.view.enterFullScreen",
        alternate: "ui.menu.view.exitFullScreen",
        key: "f",
        modifiers: [.command, .control],
        action: .toggleFullScreen,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  /// The Controller menu: the target row, Suspend or Resume, Test Input, Disconnect Wireless Link
  /// and Show in Window.
  private static let controllerSection = MainMenuSection(
    id: "controller",
    titleKey: "ui.menu.controller.title",
    entries: [
      entry(
        "controllerTarget",
        noControllerTitleKey,
        action: .controllerTarget,
        enabled: .never,
        gui: .area(.controllers)
      ),
      .separator,
      entry(
        "suspendOrResume",
        "ui.menu.controller.suspend",
        alternate: "ui.menu.controller.resume",
        action: .suspendOrResumeController,
        enabled: .requires([.controller]),
        gui: .area(.controllers)
      ),
      entry(
        "testInput",
        "ui.menu.controller.testInput",
        action: .testInput,
        enabled: .requires([.controller, .mainWindow]),
        gui: .area(.controllers)
      ),
      entry(
        "disconnectWirelessLink",
        "ui.menu.controller.disconnectWirelessLink",
        action: .disconnectWirelessLink,
        enabled: .requires([.controller, .wirelessController]),
        gui: .area(.controllers)
      ),
      .separator,
      entry(
        "showControllerInWindow",
        "ui.menu.controller.showInWindow",
        action: .showControllerInWindow,
        enabled: .requires([.mainWindow]),
        gui: .area(.controllers)
      ),
    ]
  )

  /// The Profile menu: Activate Profile, Deactivate Profile and the Profiles commands of the
  /// toolbar.
  private static let profileSection = MainMenuSection(
    id: "profile",
    titleKey: "ui.menu.profile.title",
    entries: [
      entry(
        "activateProfile",
        "ui.menu.profile.activate",
        action: .activateProfile,
        enabled: .always,
        gui: .area(.profiles)
      ),
      entry(
        "deactivateProfile",
        "ui.menu.profile.deactivate",
        action: .deactivateProfile,
        enabled: .requires([.controller, .controllerHasActiveProfile]),
        gui: .area(.profiles)
      ),
      .separator,
      toolbarEntry(.newProfile),
      toolbarEntry(.duplicateProfile),
      toolbarEntry(.convertProfile),
      toolbarEntry(.deleteProfile),
      toolbarEntry(.validateProfileFile),
    ]
  )

  /// The Window menu: Minimize, Zoom and Bring All to Front.
  private static let windowSection = MainMenuSection(
    id: "window",
    titleKey: "ui.menu.window.title",
    entries: [
      entry(
        "minimize",
        "ui.menu.window.minimize",
        key: "m",
        action: .minimize,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      entry(
        "zoom",
        "ui.menu.window.zoom",
        action: .zoom,
        enabled: .responderChain,
        gui: .standardCommand
      ),
      .separator,
      entry(
        "bringAllToFront",
        "ui.menu.window.bringAllToFront",
        action: .bringAllToFront,
        enabled: .responderChain,
        gui: .standardCommand
      ),
    ]
  )

  /// The Help menu: the Activity area, Explain Error Code, Copy Support Report, Help for This Area,
  /// Report Problem and the project page.
  private static let helpSection = MainMenuSection(
    id: "help",
    titleKey: "ui.menu.help.title",
    entries: [
      entry(
        "showActivityLog",
        "ui.menu.help.activityLog",
        action: .showActivityLog,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "explainErrorCode",
        "ui.menu.help.explainErrorCode",
        action: .explainErrorCode,
        enabled: needsMainWindow,
        gui: .area(.activity)
      ),
      entry(
        "copySupportReport",
        "ui.menu.help.copySupportReport",
        action: .copySupportReport,
        gui: .area(.activity)
      ),
      .separator,
      entry(
        "openAreaHelp",
        "ui.menu.help.helpForThisArea",
        action: .openAreaHelp,
        gui: .externalLink
      ),
      entry(
        "showMainWindowTour",
        "ui.menu.help.mainWindowTour",
        action: .showMainWindowTour,
        enabled: needsMainWindow,
        gui: .area(.controllers)
      ),
      entry(
        "reportProblem",
        "ui.menu.help.reportProblem",
        action: .reportProblem,
        gui: .externalLink
      ),
      entry(
        "openProjectWebsite",
        "ui.menu.help.projectWebsite",
        action: .openProjectWebsite,
        gui: .externalLink
      ),
    ]
  )
}
