#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// An area action shown in the main window's toolbar while its area is selected.
  enum MainWindowToolbarAction: String, CaseIterable {
    /// Starts a new profile.
    case newProfile
    /// Chooses a profile file to import.
    case importProfile
    /// Checks a profile file without importing it.
    case validateProfileFile
    /// Duplicates the selected profile.
    case duplicateProfile
    /// Saves the selected profile to a file.
    case exportProfile
    /// Asks to delete the selected profile.
    case deleteProfile
    /// Installs a controller record or mod folder into the Library.
    case installLibraryItem
    /// Grants a program access to the service.
    case grantProgram
    /// Opens the form that creates an access token.
    case createToken
    /// Validates a controller record or mod folder.
    case validateLibraryItem
    /// Tests the selected Library record against a capture and its expectation.
    case testLibraryRecord
    /// Asks to remove the selected Library item.
    case removeLibraryItem
    /// The Library search field.
    case searchLibrary
    /// The view switch of Activity.
    case activityMode
    /// The menu of the log stream filter and line count.
    case activityFilter
    /// The Activity log search field.
    case activitySearch
    /// Copies the visible log lines.
    case copyActivityLog
    /// Saves the logs to a file.
    case saveActivityLog
    /// Reveals the log file in Finder.
    case showActivityLogInFinder
    /// Runs the diagnostic checks.
    case runDiagnostics

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

    /// The SF Symbol of the toolbar item.
    var symbolName: String {
      switch self {
      case .newProfile: return "plus"
      case .importProfile: return "square.and.arrow.down"
      case .validateProfileFile: return "checkmark.seal"
      case .duplicateProfile: return "plus.square.on.square"
      case .exportProfile: return "square.and.arrow.up"
      case .deleteProfile: return "trash"
      case .installLibraryItem: return "square.and.arrow.down.on.square"
      case .grantProgram: return "person.badge.plus"
      case .createToken: return "key"
      case .validateLibraryItem: return "checkmark.circle"
      case .testLibraryRecord: return "play.circle"
      case .removeLibraryItem: return "trash"
      case .searchLibrary: return "magnifyingglass"
      case .activityMode: return "list.bullet.rectangle"
      case .activityFilter: return "line.3.horizontal.decrease.circle"
      case .activitySearch: return "magnifyingglass"
      case .copyActivityLog: return "doc.on.doc"
      case .saveActivityLog: return "square.and.arrow.down"
      case .showActivityLogInFinder: return "folder"
      case .runDiagnostics: return "stethoscope"
      }
    }

    /// The localization key of the item's label.
    var labelKey: String {
      switch self {
      case .newProfile: return "ui.profiles.new"
      case .importProfile: return "ui.profiles.import"
      case .validateProfileFile: return "ui.profiles.validateFile"
      case .duplicateProfile: return "action.duplicate"
      case .exportProfile: return "ui.profiles.export"
      case .deleteProfile: return "action.delete"
      case .installLibraryItem: return "ui.library.install"
      case .grantProgram: return "ui.access.grantProgram"
      case .createToken: return "ui.access.grantToken"
      case .validateLibraryItem: return "ui.library.validate"
      case .testLibraryRecord: return "ui.library.testRecord"
      case .removeLibraryItem: return "ui.library.remove"
      case .searchLibrary: return "ui.library.search"
      case .activityMode: return "ui.sidebar.activity.title"
      case .activityFilter: return "ui.activity.filter"
      case .activitySearch: return "ui.activity.search"
      case .copyActivityLog: return "action.copyAll"
      case .saveActivityLog: return "ui.menu.file.saveActivityLog"
      case .showActivityLogInFinder: return "platform.macos.ui.activity.showInFinder"
      case .runDiagnostics: return "ui.activity.runChecks"
      }
    }

    /// The localization key of the item's tooltip and accessibility description.
    var descriptionKey: String {
      switch self {
      case .newProfile: return "ui.profiles.new"
      case .importProfile: return "ui.profiles.import"
      case .validateProfileFile: return "ui.profiles.validateFile"
      case .duplicateProfile: return "action.duplicate"
      case .exportProfile: return "ui.profiles.export"
      case .deleteProfile: return "action.delete"
      case .installLibraryItem: return "ui.menu.file.installRecordOrMod"
      case .grantProgram: return "a11y.access.grantProgram"
      case .createToken: return "a11y.access.grantToken"
      case .validateLibraryItem: return "ui.library.validate"
      case .testLibraryRecord: return "ui.library.testRecord"
      case .removeLibraryItem: return "ui.library.remove"
      case .searchLibrary: return "ui.library.search"
      case .activityMode: return "ui.sidebar.activity.title"
      case .activityFilter: return "ui.activity.filter"
      case .activitySearch: return "ui.activity.search"
      case .copyActivityLog: return "action.copyAll"
      case .saveActivityLog: return "ui.menu.file.saveActivityLog"
      case .showActivityLogInFinder: return "platform.macos.ui.activity.showInFinder"
      case .runDiagnostics: return "ui.activity.runChecks"
      }
    }
  }

  /// What decides whether the Profiles toolbar actions are enabled.
  struct ProfileToolbarState: Equatable {
    /// A profile of the library is selected.
    let hasSelection: Bool
    /// A mutation or recovery is running, or the library has damaged entries.
    let isBlocked: Bool
    /// The editor holds changes that are not saved.
    let hasUnsavedChanges: Bool
  }

  extension MainWindowToolbarAction {
    /// Whether the action acts on the saved profile.
    ///
    /// Duplicate and Export wait for the editor's changes to be saved.
    var needsSavedProfile: Bool { self == .duplicateProfile || self == .exportProfile }

    /// Whether a Profiles action is enabled in `state`; other actions are always enabled here.
    func isEnabled(profile state: ProfileToolbarState) -> Bool {
      switch self {
      case .newProfile, .importProfile: return !state.isBlocked
      case .validateProfileFile: return true
      case .exportProfile: return state.hasSelection && !state.hasUnsavedChanges
      case .duplicateProfile:
        return state.hasSelection && !state.isBlocked && !state.hasUnsavedChanges
      case .deleteProfile: return state.hasSelection && !state.isBlocked
      case .installLibraryItem, .grantProgram, .createToken,
        .validateLibraryItem, .testLibraryRecord, .removeLibraryItem, .searchLibrary:
        return true
      case .activityMode, .activityFilter, .activitySearch, .copyActivityLog, .saveActivityLog,
        .showActivityLogInFinder, .runDiagnostics:
        return true
      }
    }
  }

  extension MainWindowArea {
    /// The toolbar actions of the area, in order.
    ///
    /// Activity's depend on which of its views is shown.
    func toolbarActions(activityMode: ActivityMode) -> [MainWindowToolbarAction] {
      switch self {
      case .controllers: return []
      case .profiles:
        return [
          .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .exportProfile,
          .deleteProfile,
        ]
      case .library:
        return [
          .installLibraryItem, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
          .searchLibrary,
        ]
      case .access: return [.grantProgram, .createToken]
      case .activity:
        switch activityMode {
        case .log:
          return [
            .activityMode, .activityFilter, .activitySearch, .copyActivityLog,
            .saveActivityLog, .showActivityLogInFinder,
          ]
        case .diagnostics: return [.activityMode, .runDiagnostics]
        }
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

    /// The identifier of the main window's toolbar.
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
      let description = OJDLocalized.string(action.descriptionKey)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = description
      item.image = NSImage(
        systemSymbolName: action.symbolName,
        accessibilityDescription: description
      )
      item.isBordered = true
      if let search = item as? NSSearchToolbarItem {
        search.fixSearchFieldWidth()
      }
      return item
    }
  }

#endif
