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

  /// The SF Symbol, the label key and the tooltip key of the toolbar item.
  private var presentation: (symbol: String, label: String, description: String) {
    switch self {
    case .newProfile: ("plus", "ui.profiles.new", "ui.help.newProfile")
    case .importProfile: ("square.and.arrow.down", "ui.profiles.import", "ui.help.importProfile")
    case .validateProfileFile:
      ("checkmark.seal", "ui.profiles.validateFile", "ui.help.validateProfileFile")
    case .duplicateProfile:
      ("plus.square.on.square", "action.duplicate", "ui.help.duplicateProfile")
    case .convertProfile: ("arrow.left.arrow.right", "action.convert", "ui.help.convertProfile")
    case .exportProfile: ("square.and.arrow.up", "ui.profiles.export", "ui.help.exportProfile")
    case .deleteProfile: ("trash", "action.delete", "ui.help.deleteProfile")
    case .installLibraryItem:
      ("square.and.arrow.down.on.square", "ui.library.install", "ui.help.menu.installRecordOrMod")
    case .grantProgram: ("person.badge.plus", "ui.access.grantProgram", "a11y.access.grantProgram")
    case .createToken: ("key", "ui.access.grantToken", "a11y.access.grantToken")
    case .validateLibraryItem:
      ("checkmark.circle", "ui.library.validate", "ui.help.validateLibraryItem")
    case .testLibraryRecord: ("play.circle", "ui.library.testRecord", "ui.help.testLibraryRecord")
    case .removeLibraryItem: ("trash", "ui.library.remove", "ui.help.removeLibraryItem")
    case .searchLibrary: ("magnifyingglass", "ui.library.search", "ui.help.searchLibrary")
    case .activityMode:
      ("list.bullet.rectangle", "ui.sidebar.activity.title", "ui.help.activityMode")
    case .activityFilter:
      ("line.3.horizontal.decrease.circle", "ui.activity.filter", "ui.help.activityFilter")
    case .activitySearch: ("magnifyingglass", "ui.activity.search", "ui.help.activitySearch")
    case .copyActivityLog: ("doc.on.doc", "action.copyAll", "ui.help.copyActivityLog")
    case .saveActivityLog:
      ("square.and.arrow.down", "ui.menu.file.saveActivityLog", "ui.help.saveActivityLog")
    case .showActivityLogInFinder:
      (
        "folder", "platform.macos.ui.activity.showInFinder",
        "platform.macos.ui.help.showActivityLog"
      )
    case .runDiagnostics: ("stethoscope", "ui.activity.runChecks", "ui.help.runDiagnostics")
    }
  }

  /// The SF Symbol of the toolbar item.
  var symbolName: String { presentation.symbol }

  /// The localization key of the item's label.
  var labelKey: String { presentation.label }

  /// The localization key of the item's tooltip.
  var descriptionKey: String { presentation.description }

  /// The area that offers the action, in its toolbar or its menu.
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
    case .installLibraryItem, .grantProgram, .createToken, .validateLibraryItem,
      .testLibraryRecord, .removeLibraryItem, .searchLibrary, .activityMode, .activityFilter,
      .activitySearch, .copyActivityLog, .saveActivityLog, .showActivityLogInFinder,
      .runDiagnostics:
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
    case .profiles: return [.newProfile, .importProfile, .exportProfile, .deleteProfile]
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

  /// The actions of the area that the main menu runs: the toolbar actions, then the ones that only
  /// the menu offers.
  ///
  /// Duplicate, Convert and Check Profile File stay in the Profile menu so the toolbar keeps to the
  /// frequent commands, per the HIG's toolbar guidance.
  func commandActions(activityMode: ActivityMode) -> [MainWindowToolbarAction] {
    switch self {
    case .profiles:
      return toolbarActions(activityMode: activityMode) + [
        .duplicateProfile, .convertProfile, .validateProfileFile,
      ]
    case .controllers, .library, .access, .activity:
      return toolbarActions(activityMode: activityMode)
    }
  }

  /// The search field action of the list that the area shows, or nil when it has none.
  func searchAction(activityMode: ActivityMode) -> MainWindowToolbarAction? {
    toolbarActions(activityMode: activityMode).first { $0.menuAction == .find }
  }
}
