#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  extension MainWindowToolbarAction {
    /// The toolbar item identifier of the action.
    var identifier: NSToolbarItem.Identifier {
      NSToolbarItem.Identifier("OpenJoystickDriver.MainWindowToolbar.\(rawValue)")
    }

    /// Creates the action whose ``identifier`` is `identifier`, or nil when none matches.
    init?(identifier: NSToolbarItem.Identifier) {
      guard let action = Self.allCases.first(where: { $0.identifier == identifier }) else {
        return nil
      }
      self = action
    }
  }

  extension MainWindowArea {
    /// The toolbar actions of the area that show at `level`.
    func toolbarActions(
      activityMode: ActivityMode,
      level: InterfaceLevel,
      developerToolsEnabled: Bool
    ) -> [MainWindowToolbarAction] {
      toolbarActions(activityMode: activityMode).filter {
        $0.interfaceRowLevel.isShown(at: level, developerToolsEnabled: developerToolsEnabled)
      }
    }
  }

  extension NSSearchToolbarItem {
    /// Keeps the search field at the toolbar's search width instead of growing into the free
    /// toolbar space.
    func fixSearchFieldWidth() {
      preferredWidthForSearchField = MainWindowToolbarLayout.searchFieldWidth
      searchField.widthAnchor.constraint(
        lessThanOrEqualToConstant: MainWindowToolbarLayout.searchFieldWidth
      ).isActive = true
    }
  }

  /// The toolbar layout of the main window: the sidebar toggle, then the separator that follows the
  /// sidebar's edge, then flexible space that pushes the selected area's actions to the trailing
  /// edge.
  ///
  /// The window title and subtitle sit after the separator.
  enum MainWindowToolbarLayout {
    /// The width of a toolbar search field, as in Mail and Finder.
    static let searchFieldWidth: CGFloat = 220

    /// The prefix of each main window toolbar's identifier.
    static let toolbar = NSToolbar.Identifier("OpenJoystickDriver.MainWindowToolbar")

    /// The items that every area shows, before its actions.
    static let fixedItems: [NSToolbarItem.Identifier] = [
      .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
    ]

    /// Returns the fixed items followed by the actions of `area`.
    static func items(
      for area: MainWindowArea,
      activityMode: ActivityMode
    ) -> [NSToolbarItem.Identifier] {
      fixedItems + area.toolbarActions(activityMode: activityMode).map(\.identifier)
    }

    /// Returns the fixed items and every action.
    static var allowedItems: [NSToolbarItem.Identifier] {
      fixedItems + MainWindowToolbarAction.allCases.map(\.identifier)
    }

    /// Returns a toolbar item for `action`, with its label, tooltip and symbol.
    ///
    /// The Library search action gets a search field item.
    @MainActor
    static func makeItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item =
        action == .searchLibrary
        ? NSSearchToolbarItem(itemIdentifier: action.identifier)
        : NSToolbarItem(itemIdentifier: action.identifier)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = action.descriptionKey.map { OJDLocalized.string($0) }
      item.image = NSImage(
        systemSymbolName: action.symbolName,
        accessibilityDescription: item.toolTip ?? item.label
      )
      item.isBordered = true
      if let search = item as? NSSearchToolbarItem {
        search.fixSearchFieldWidth()
        search.searchField.placeholderString = item.label
      }
      return item
    }
  }

#endif
