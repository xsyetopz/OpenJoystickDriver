import Foundation

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
  /// Converts the selected profile to another controller model.
  case convertProfile
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

  /// The interface level that shows the item: profile items are Simple, Library and Activity items
  /// are Advanced, and Access items are Developer.
  var interfaceRowLevel: InterfaceRowLevel {
    switch self {
    case .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .convertProfile,
      .exportProfile, .deleteProfile:
      return .simple
    case .installLibraryItem, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
      .searchLibrary, .activityMode, .activityFilter, .activitySearch, .copyActivityLog,
      .saveActivityLog, .showActivityLogInFinder, .runDiagnostics:
      return .advanced
    case .grantProgram, .createToken:
      return .developer
    }
  }

  /// The SF Symbol of the toolbar item.
  var symbolName: String {
    switch self {
    case .newProfile: return "plus"
    case .importProfile: return "square.and.arrow.down"
    case .validateProfileFile: return "checkmark.seal"
    case .duplicateProfile: return "plus.square.on.square"
    case .convertProfile: return "arrow.left.arrow.right"
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
    case .convertProfile: return "action.convert"
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

  /// The localization key of the item's tooltip.
  var descriptionKey: String {
    switch self {
    case .newProfile: return "ui.help.newProfile"
    case .importProfile: return "ui.help.importProfile"
    case .validateProfileFile: return "ui.help.validateProfileFile"
    case .duplicateProfile: return "ui.help.duplicateProfile"
    case .convertProfile: return "ui.help.convertProfile"
    case .exportProfile: return "ui.help.exportProfile"
    case .deleteProfile: return "ui.help.deleteProfile"
    case .installLibraryItem: return "ui.menu.file.installRecordOrMod"
    case .grantProgram: return "a11y.access.grantProgram"
    case .createToken: return "a11y.access.grantToken"
    case .validateLibraryItem: return "ui.help.validateLibraryItem"
    case .testLibraryRecord: return "ui.help.testLibraryRecord"
    case .removeLibraryItem: return "ui.help.removeLibraryItem"
    case .searchLibrary: return "ui.help.searchLibrary"
    case .activityMode: return "ui.help.activityMode"
    case .activityFilter: return "ui.help.activityFilter"
    case .activitySearch: return "ui.help.activitySearch"
    case .copyActivityLog: return "ui.help.copyActivityLog"
    case .saveActivityLog: return "ui.help.saveActivityLog"
    case .showActivityLogInFinder: return "platform.macos.ui.help.showActivityLog"
    case .runDiagnostics: return "ui.help.runDiagnostics"
    }
  }

  /// The area whose toolbar shows the action.
  var area: MainWindowArea {
    switch self {
    case .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .convertProfile,
      .exportProfile, .deleteProfile:
      return .profiles
    case .installLibraryItem, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
      .searchLibrary:
      return .library
    case .grantProgram, .createToken: return .access
    case .activityMode, .activityFilter, .activitySearch, .copyActivityLog, .saveActivityLog,
      .showActivityLogInFinder, .runDiagnostics:
      return .activity
    }
  }

  /// The main menu action that does what the toolbar item does: the File menu's own command
  /// where one exists, Find for a search field, else a command of the toolbar action.
  var menuAction: MainMenuAction {
    switch self {
    case .importProfile: return .importProfile
    case .exportProfile: return .exportProfile
    case .installLibraryItem: return .installRecordOrMod
    case .saveActivityLog: return .saveActivityLog
    case .searchLibrary, .activitySearch: return .find
    default: return .toolbar(self)
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
  /// Duplicate, Convert and Export wait for the editor's changes to be saved.
  var needsSavedProfile: Bool {
    self == .duplicateProfile || self == .convertProfile || self == .exportProfile
  }

  /// Whether a Profiles action is enabled in `state`; other actions are always enabled here.
  func isEnabled(profile state: ProfileToolbarState) -> Bool {
    switch self {
    case .newProfile, .importProfile: return !state.isBlocked
    case .validateProfileFile: return true
    case .exportProfile: return state.hasSelection && !state.hasUnsavedChanges
    case .duplicateProfile, .convertProfile:
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
        .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .convertProfile,
        .exportProfile, .deleteProfile,
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

  /// The search field action of the list that the area shows, or nil when it has none.
  func searchAction(activityMode: ActivityMode) -> MainWindowToolbarAction? {
    toolbarActions(activityMode: activityMode).first { $0.menuAction == .find }
  }
}
