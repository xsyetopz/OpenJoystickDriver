#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  extension MainWindowController {
    /// Returns the Activity toolbar item for `action` when it is not a plain button, else nil.
    ///
    /// The items are the view switch, the stream filter, the line count and the search field.
    func makeActivityControlItem(for action: MainWindowToolbarAction) -> NSToolbarItem? {
      switch action {
      case .activityMode:
        return makeSegmentedItem(
          for: action,
          titleKeys: ActivityMode.allCases.map(\.titleKey),
          selectedIndex: screens.activity.mode.rawValue,
          selector: #selector(selectActivityMode(_:))
        )
      case .activityFilter: return makeFilterItem(for: action)
      case .activitySearch: return makeSearchItem(for: action)
      case .newProfile, .importProfile, .validateProfileFile,
        .duplicateProfile, .convertProfile, .exportProfile, .deleteProfile, .installLibraryItem,
        .grantProgram, .createToken, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
        .searchLibrary, .copyActivityLog, .saveActivityLog, .showActivityLogInFinder,
        .runDiagnostics:
        return nil
      }
    }

    /// Returns a segmented toolbar group that selects one of `titleKeys`, starting at
    /// `selectedIndex`.
    private func makeSegmentedItem(
      for action: MainWindowToolbarAction,
      titleKeys: [String],
      selectedIndex: Int,
      selector: Selector
    ) -> NSToolbarItem {
      let group = NSToolbarItemGroup(
        itemIdentifier: action.identifier,
        titles: titleKeys.map { OJDLocalized.string($0) },
        selectionMode: .selectOne,
        labels: nil,
        target: self,
        action: selector
      )
      group.controlRepresentation = .expanded
      group.selectedIndex = selectedIndex
      // The segments name the views; the label would repeat the sidebar's Activity item, so only
      // the palette and VoiceOver get it.
      let label = OJDLocalized.string(action.labelKey)
      group.label = ""
      group.paletteLabel = label
      group.toolTip = OJDLocalized.string(action.descriptionKey)
      group.view?.setAccessibilityLabel(label)
      return group
    }

    /// Returns the filter menu item: the stream filter choices and the line count choices.
    ///
    /// One menu holds both, so the toolbar fits at the window's minimum width without an overflow
    /// chevron.
    private func makeFilterItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item = NSMenuToolbarItem(itemIdentifier: action.identifier)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = OJDLocalized.string(action.descriptionKey)
      item.image = NSImage(
        systemSymbolName: action.symbolName,
        accessibilityDescription: item.label
      )
      item.showsIndicator = true
      item.menu = Self.makeActivityFilterMenu(title: "", target: self)
      return item
    }

    /// Returns the menu of the stream filter choices and the line count choices.
    ///
    /// The toolbar item targets the window controller; the View menu leaves the target nil, so the
    /// choices reach the key window's controller through the responder chain.
    static func makeActivityFilterMenu(title: String, target: AnyObject? = nil) -> NSMenu {
      let menu = NSMenu(title: title)
      for filter in ActivityLogFilter.allCases {
        let entry = NSMenuItem(
          title: OJDLocalized.string(filter.titleKey),
          action: #selector(selectActivityFilter(_:)),
          keyEquivalent: ""
        )
        entry.toolTip = OJDLocalized.string("ui.help.activityFilterChoice")
        entry.target = target
        entry.tag = filter.rawValue
        menu.addItem(entry)
      }
      menu.addItem(.separator())
      let heading = NSMenuItem(
        title: OJDLocalized.string("ui.activity.lines"),
        action: nil,
        keyEquivalent: ""
      )
      heading.isEnabled = false
      menu.addItem(heading)
      for count in ActivityLogLineCount.choices {
        let entry = NSMenuItem(
          title: count.formatted(),
          action: #selector(selectActivityLineCount(_:)),
          keyEquivalent: ""
        )
        entry.toolTip = OJDLocalized.string("ui.help.activityLineCount")
        entry.target = target
        entry.tag = count
        menu.addItem(entry)
      }
      return menu
    }

    /// Returns the menu that chooses the view of Activity, which the View menu shows.
    static func makeActivityModeMenu(title: String) -> NSMenu {
      let menu = NSMenu(title: title)
      for mode in ActivityMode.allCases {
        let entry = NSMenuItem(
          title: OJDLocalized.string(mode.titleKey),
          action: #selector(selectActivityModeFromMenu(_:)),
          keyEquivalent: ""
        )
        entry.toolTip = OJDLocalized.string("ui.help.activityModeChoice")
        entry.tag = mode.rawValue
        menu.addItem(entry)
      }
      return menu
    }

    /// Switches the Activity area to the view of the chosen menu item and moves the toolbar's view
    /// switch with it.
    @objc
    func selectActivityModeFromMenu(_ sender: NSMenuItem) {
      guard let mode = ActivityMode(rawValue: sender.tag) else { return }
      screens.activity.mode = mode
      let switcher = window?.toolbar?.items.first {
        $0.itemIdentifier == MainWindowToolbarAction.activityMode.identifier
      }
      (switcher as? NSToolbarItemGroup)?.selectedIndex = mode.rawValue
    }

    /// Returns the search field item of the Activity toolbar, filled with the current search text.
    private func makeSearchItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item = NSSearchToolbarItem(itemIdentifier: action.identifier)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = OJDLocalized.string(action.descriptionKey)
      item.fixSearchFieldWidth()
      item.searchField.placeholderString = item.label
      item.searchField.stringValue = screens.activity.log.searchText
      item.searchField.sendsSearchStringImmediately = true
      item.searchField.target = self
      item.searchField.action = #selector(searchActivityLog(_:))
      return item
    }

    /// Switches the Activity area between its views.
    @objc
    func selectActivityMode(_ sender: NSToolbarItemGroup) {
      guard let mode = ActivityMode(rawValue: sender.selectedIndex) else { return }
      screens.activity.mode = mode
    }

    /// Sets the Activity log's stream filter from the chosen menu item.
    @objc
    func selectActivityFilter(_ sender: NSMenuItem) {
      guard let filter = ActivityLogFilter(rawValue: sender.tag) else { return }
      screens.activity.log.filter = filter
    }

    /// Sets how many log lines the Activity area shows and the support report exports.
    @objc
    func selectActivityLineCount(_ sender: NSMenuItem) {
      screens.activity.log.setLineCount(sender.tag)
      screens.supportReport.logExportLines = sender.tag
    }

    /// Filters the Activity log by the text in the toolbar search field.
    @objc
    func searchActivityLog(_ sender: NSSearchField) {
      screens.activity.log.searchText = sender.stringValue
    }

    /// Asks where to save the end of the logs, then writes them as `ojd log export` does.
    ///
    /// Uses the same model as the Save Activity Log menu item. A failed save shows in the Activity
    /// area.
    func saveActivityLog() {
      guard let window else { return }
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.debug.saveLogsPanel")
      panel.message = ApplicationServiceLogService.sharingWarning
      panel.nameFieldStringValue = screens.supportReport.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
          guard let self else { return }
          await self.screens.supportReport.saveSupportLogs(to: url)
          if case .error(let message) = self.screens.supportReport.supportLogsState {
            self.screens.activity.failure = ActivityActionFailure(
              title: OJDLocalized.string("ui.menu.file.saveFailed"),
              message: message
            )
          }
        }
      }
    }

    /// Reveals the Activity log file in Finder, and shows a failure in the Activity area when it
    /// cannot.
    func showActivityLogInFinder() {
      if !screens.activity.log.showInFinder() {
        screens.activity.failure = ActivityActionFailure(
          title: OJDLocalized.string("ui.activity.showInFinder.failed"),
          message: nil
        )
      }
    }

    /// Follows the logs while the window is visible and shows the log, and stops otherwise.
    ///
    /// `area` is the selected area. The area observer passes the area being selected, because
    /// `@Published` sends it before `navigation.selectedArea` holds it.
    func updateLogFollowing(area: MainWindowArea) {
      guard let window else { return }
      screens.activity.log.setFollowing(
        ActivityLogFollowing.shouldFollow(
          windowVisible: window.isVisible && !window.isMiniaturized,
          area: area,
          mode: screens.activity.mode
        )
      )
    }
  }

  extension MainWindowController: NSMenuItemValidation {
    /// Marks the selected line count or filter in the Activity menus and keeps every item enabled.
    ///
    /// - Parameter menuItem: The menu item to check.
    /// - Returns: Always true.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      if menuItem.action == #selector(selectActivityLineCount(_:)) {
        menuItem.state = menuItem.tag == screens.activity.log.lineCount ? .on : .off
      } else if menuItem.action == #selector(selectActivityFilter(_:)) {
        menuItem.state = menuItem.tag == screens.activity.log.filter.rawValue ? .on : .off
      } else if menuItem.action == #selector(selectActivityModeFromMenu(_:)) {
        menuItem.state = menuItem.tag == screens.activity.mode.rawValue ? .on : .off
      }
      return true
    }
  }

#endif
