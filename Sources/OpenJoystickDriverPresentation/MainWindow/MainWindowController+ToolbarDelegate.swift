#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit

  extension MainWindowController: NSToolbarDelegate {
    /// Returns the fixed items and every area action.
    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.allowedItems
    }

    /// Returns the fixed items and the actions of the selected area.
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.fixedItems
        + shownToolbarActions(of: navigation.selectedArea).map(\.identifier)
    }

    /// Returns no identifiers, because no toolbar item stays selected.
    func toolbarSelectableItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      []
    }

    /// Returns the toolbar item for `itemIdentifier`: the sidebar separator or an area action.
    func toolbar(
      _: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
      if itemIdentifier == .sidebarTrackingSeparator {
        return NSTrackingSeparatorToolbarItem(
          identifier: itemIdentifier,
          splitView: splitViewController.splitView,
          dividerIndex: 0
        )
      }
      guard let action = MainWindowToolbarAction(identifier: itemIdentifier) else { return nil }
      if let item = makeActivityControlItem(for: action) { return item }
      let item = MainWindowToolbarLayout.makeItem(for: action)
      if let search = item as? NSSearchToolbarItem {
        search.searchField.stringValue = screens.libraryArea.searchText
        search.searchField.target = self
        search.searchField.action = #selector(librarySearchChanged(_:))
        return search
      }
      item.target = self
      item.action = #selector(performToolbarAction(_:))
      return item
    }
  }

#endif
