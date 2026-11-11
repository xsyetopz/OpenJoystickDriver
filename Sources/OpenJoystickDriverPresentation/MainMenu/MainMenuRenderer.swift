#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit

  /// The menus ``MainMenuRenderer`` built, with the ones AppKit tracks by role.
  struct RenderedMainMenu {
    /// The menu bar.
    let menu: NSMenu
    /// The Services submenu, which macOS fills.
    let servicesMenu: NSMenu
    /// The Window menu.
    let windowMenu: NSMenu
    /// The Help menu.
    let helpMenu: NSMenu
  }

  /// Renders ``MainMenuModel`` to an `NSMenu`.
  ///
  /// Items that act through the responder chain keep a nil target; every other item targets the
  /// coordinator, which performs the action by item id.
  @MainActor
  enum MainMenuRenderer {
    /// Returns the menus built from ``MainMenuModel``; `target` performs the actions that do not go
    /// through the responder chain.
    static func render(target: MenuBarCoordinator) -> RenderedMainMenu {
      let appName = OJDLocalized.string("term.app.name")
      let menu = NSMenu(title: appName)
      let servicesMenu = NSMenu(title: OJDLocalized.string("ui.menu.app.services"))
      var windowMenu: NSMenu?
      var helpMenu: NSMenu?
      for section in MainMenuModel.sections {
        let submenu = NSMenu(title: title(section.titleKey, appName: appName))
        submenu.delegate = target
        for entry in section.entries {
          switch entry {
          case .separator: submenu.addItem(.separator())
          case .item(let item):
            submenu.addItem(
              makeItem(item, appName: appName, target: target, servicesMenu: servicesMenu)
            )
          }
        }
        let sectionItem = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        identify(sectionItem, as: MainMenuModel.menuBarItemIdentifier(sectionID: section.id))
        sectionItem.submenu = submenu
        menu.addItem(sectionItem)
        if section.id == "window" { windowMenu = submenu }
        if section.id == "help" { helpMenu = submenu }
      }
      guard let windowMenu, let helpMenu else {
        preconditionFailure("The main menu model has no Window or Help section")
      }
      return RenderedMainMenu(
        menu: menu,
        servicesMenu: servicesMenu,
        windowMenu: windowMenu,
        helpMenu: helpMenu
      )
    }

    /// The text of a title that is a localization key or data such as a controller name.
    static func text(of title: StatusItemTitle) -> String {
      switch title {
      case .key(let key): return OJDLocalized.string(key)
      case .verbatim(let text): return text
      case .formatted(let key, let argument):
        return OJDLocalized.formatted(key, text(of: argument))
      }
    }

    /// Gives the item its model id as its identifier, which the coordinator looks items up by,
    /// and as its accessibility identifier, so Accessibility clients such as
    /// `Scripts/GUI/ax.js` find it in every language.
    static func identify(_ menuItem: NSMenuItem, as id: String) {
      menuItem.identifier = NSUserInterfaceItemIdentifier(id)
      menuItem.setAccessibilityIdentifier(id)
    }

    /// Returns the localized title for `key`, with the app name filled in when the text has a
    /// placeholder.
    static func title(_ key: String, appName: String) -> String {
      let text = OJDLocalized.string(key)
      return text.contains("%@") ? unsafe String(format: text, appName) : text
    }

    /// Returns the menu item for `item`, attached as ``routing(for:)`` says.
    private static func makeItem(
      _ item: MainMenuItem,
      appName: String,
      target: MenuBarCoordinator,
      servicesMenu: NSMenu
    ) -> NSMenuItem {
      let menuItem = NSMenuItem(
        title: title(item.titleKey, appName: appName),
        action: nil,
        keyEquivalent: item.keyEquivalent
      )
      identify(menuItem, as: item.id)
      menuItem.keyEquivalentModifierMask = modifierMask(item.modifiers)
      switch routing(for: item.action) {
      case .services:
        menuItem.submenu = servicesMenu
      case .profileSubmenu:
        let profiles = NSMenu(title: menuItem.title)
        profiles.delegate = target
        menuItem.submenu = profiles
      case .activityChoices:
        menuItem.submenu =
          item.action == .toolbar(.activityMode)
          ? MainWindowController.makeActivityModeMenu(title: menuItem.title)
          : MainWindowController.makeActivityFilterMenu(title: menuItem.title)
      case .responder(let selector):
        menuItem.action = selector
      case .informational:
        break
      case .coordinator:
        menuItem.action = #selector(MenuBarCoordinator.performMainMenuItem(_:))
        menuItem.target = target
      }
      return menuItem
    }

    /// How a menu item is attached: submenu parents carry no action, so the coordinator never
    /// receives an action that only has a submenu.
    enum Routing {
      /// The item opens the Services submenu.
      case services
      /// The item opens a submenu that the coordinator fills with profiles.
      case profileSubmenu
      /// The item opens a submenu of the Activity choices, which the main window performs.
      case activityChoices
      /// The item sends the selector down the responder chain.
      case responder(Selector)
      /// The coordinator performs the action by item id.
      case coordinator
      /// A row that shows text and has no action.
      case informational
    }

    /// Returns how the item of the action is attached.
    static func routing(for action: MainMenuAction) -> Routing {
      if action == .services { return .services }
      if action == .activateProfile { return .profileSubmenu }
      if action == .controllerTarget { return .informational }
      if action == .toolbar(.activityMode) || action == .toolbar(.activityFilter) {
        return .activityChoices
      }
      if let selector = responderSelector(for: action) { return .responder(selector) }
      return .coordinator
    }

    /// Returns the AppKit modifier flags of the modifiers.
    static func modifierMask(_ modifiers: MainMenuModifiers) -> NSEvent.ModifierFlags {
      var mask: NSEvent.ModifierFlags = []
      if modifiers.contains(.command) { mask.insert(.command) }
      if modifiers.contains(.shift) { mask.insert(.shift) }
      if modifiers.contains(.option) { mask.insert(.option) }
      if modifiers.contains(.control) { mask.insert(.control) }
      return mask
    }

    /// The selector sent down the responder chain, or nil when the coordinator performs the
    /// action. `.services` is a submenu and has no selector.
    static func responderSelector(for action: MainMenuAction) -> Selector? {
      switch action {
      case .undo: return Selector(("undo:"))
      case .redo: return Selector(("redo:"))
      case .cut: return #selector(NSText.cut(_:))
      case .copy: return #selector(NSText.copy(_:))
      case .paste: return #selector(NSText.paste(_:))
      case .delete: return #selector(NSText.delete(_:))
      case .selectAll: return #selector(NSText.selectAll(_:))
      case .close: return #selector(NSWindow.performClose(_:))
      case .hide: return #selector(NSApplication.hide(_:))
      case .hideOthers: return #selector(NSApplication.hideOtherApplications(_:))
      case .showAll: return #selector(NSApplication.unhideAllApplications(_:))
      case .toggleToolbar: return #selector(NSWindow.toggleToolbarShown(_:))
      case .toggleSidebar: return #selector(NSSplitViewController.toggleSidebar(_:))
      case .toggleFullScreen: return #selector(NSWindow.toggleFullScreen(_:))
      case .minimize: return #selector(NSWindow.performMiniaturize(_:))
      case .zoom: return #selector(NSWindow.performZoom(_:))
      case .bringAllToFront: return #selector(NSApplication.arrangeInFront(_:))
      case .services, .about, .settings, .quit, .importProfile, .exportProfile,
        .installRecordOrMod, .saveSupportReport, .saveActivityLog, .showArea,
        .controllerTarget, .suspendOrResumeController, .testInput, .disconnectWirelessLink,
        .showControllerInWindow, .activateProfile, .deactivateProfile, .showActivityLog,
        .explainErrorCode, .copySupportReport, .reportProblem, .openProjectWebsite, .find,
        .toolbar:
        return nil
      }
    }
  }

#endif
