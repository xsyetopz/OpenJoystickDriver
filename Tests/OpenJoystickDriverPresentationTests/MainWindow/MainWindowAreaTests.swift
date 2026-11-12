import AppKit
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainWindowAreaTests {
  @Test
  func areasRunInToolbarOrderWithCommandDigits() {
    #expect(MainWindowArea.allCases == [.controllers, .profiles, .library, .access, .activity])
    #expect(MainWindowArea.allCases.map(\.keyEquivalent) == ["1", "2", "3", "4", "5"])
  }

  @Test
  func everyAreaHasATitleKey() {
    for area in MainWindowArea.allCases {
      #expect(area.titleKey == "ui.sidebar.\(area.rawValue).title")
    }
  }

  @Test
  func everyAreaTitleKeyIsInTheCatalog() {
    for area in MainWindowArea.allCases {
      #expect(OJDLocalized.string(area.titleKey) != area.titleKey, "\(area.titleKey)")
    }
  }

  @Test
  func onlyControllersProfilesAndLibraryHaveAListColumn() {
    #expect(MainWindowArea.allCases.filter(\.hasListColumn) == [.controllers, .profiles, .library])
  }

  @Test
  @MainActor
  func theWindowOpensOnControllersWhenNoAreaWasChosen() {
    let navigation = MainWindowNavigationModel(persistence: MemoryAreaPersistence())
    #expect(navigation.selectedArea == .controllers)
  }

  @Test
  @MainActor
  func commandTwoSelectsProfilesAndTheTitleFollows() {
    let navigation = MainWindowNavigationModel(persistence: MemoryAreaPersistence())
    let area = MainWindowArea.allCases.first { $0.keyEquivalent == "2" }
    #expect(area == .profiles)
    if let area { #expect(navigation.requestArea(area)) }
    #expect(navigation.selectedArea == .profiles)
    #expect(navigation.selectedArea.titleKey == "ui.sidebar.profiles.title")
  }

  @Test
  func toolbarHoldsTheSidebarToggleAndNoAreaSwitcher() {
    #expect(
      MainWindowToolbarLayout.fixedItems == [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
      ]
    )
    for area in MainWindowArea.allCases {
      #expect(
        MainWindowToolbarLayout.items(for: area, activityMode: .log).starts(
          with: MainWindowToolbarLayout.fixedItems
        )
      )
    }
  }

  @Test
  func eachAreaShowsItsOwnActionsAfterTheFixedItems() {
    #expect(MainWindowArea.controllers.toolbarActions(activityMode: .log).isEmpty)
    let profileActions: [MainWindowToolbarAction] = [
      .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .convertProfile,
      .exportProfile, .deleteProfile,
    ]
    #expect(MainWindowArea.profiles.toolbarActions(activityMode: .log) == profileActions)
    #expect(
      MainWindowArea.library.toolbarActions(activityMode: .log) == [
        .installLibraryItem, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
        .searchLibrary,
      ]
    )
    #expect(
      MainWindowArea.access.toolbarActions(activityMode: .log) == [.grantProgram, .createToken]
    )
    #expect(
      MainWindowToolbarLayout.items(for: .profiles, activityMode: .log)
        == MainWindowToolbarLayout.fixedItems + profileActions.map(\.identifier)
    )
  }

  @Test
  func profileActionsFollowTheSelectionTheBlockAndUnsavedChanges() {
    func enabled(_ action: MainWindowToolbarAction, _ state: ProfileToolbarState) -> Bool {
      action.isEnabled(profile: state)
    }
    let none = ProfileToolbarState(hasSelection: false, isBlocked: false, hasUnsavedChanges: false)
    let selected = ProfileToolbarState(
      hasSelection: true,
      isBlocked: false,
      hasUnsavedChanges: false
    )
    let unsaved = ProfileToolbarState(hasSelection: true, isBlocked: false, hasUnsavedChanges: true)
    let blocked = ProfileToolbarState(hasSelection: true, isBlocked: true, hasUnsavedChanges: false)
    let selectionActions: [MainWindowToolbarAction] = [
      .duplicateProfile, .convertProfile, .exportProfile, .deleteProfile,
    ]
    for action in selectionActions { #expect(!enabled(action, none)) }
    for action in selectionActions { #expect(enabled(action, selected)) }
    #expect(!enabled(.duplicateProfile, unsaved))
    #expect(!enabled(.convertProfile, unsaved))
    #expect(!enabled(.exportProfile, unsaved))
    #expect(enabled(.deleteProfile, unsaved))
    #expect(!enabled(.duplicateProfile, blocked))
    #expect(!enabled(.convertProfile, blocked))
    #expect(enabled(.exportProfile, blocked))
    #expect(!enabled(.deleteProfile, blocked))
    #expect(!enabled(.newProfile, blocked) && !enabled(.importProfile, blocked))
    #expect(enabled(.validateProfileFile, blocked))
    #expect(enabled(.newProfile, none))
    #expect(MainWindowToolbarAction.duplicateProfile.needsSavedProfile)
    #expect(MainWindowToolbarAction.exportProfile.needsSavedProfile)
    #expect(!MainWindowToolbarAction.deleteProfile.needsSavedProfile)
  }

  @Test
  func activityActionsFollowTheViewItShows() {
    #expect(
      MainWindowArea.activity.toolbarActions(activityMode: .log) == [
        .activityMode, .activityFilter, .activitySearch, .copyActivityLog,
        .saveActivityLog, .showActivityLogInFinder,
      ]
    )
    #expect(
      MainWindowArea.activity.toolbarActions(activityMode: .diagnostics) == [
        .activityMode, .runDiagnostics,
      ]
    )
    #expect(
      MainWindowToolbarLayout.items(for: .activity, activityMode: .diagnostics)
        == MainWindowToolbarLayout.fixedItems + [
          MainWindowToolbarAction.activityMode.identifier,
          MainWindowToolbarAction.runDiagnostics.identifier,
        ]
    )
  }

  @Test
  func everyActionIsAllowedHasDistinctIdentifierAndLocalizedText() {
    let actions = MainWindowToolbarAction.allCases
    #expect(Set(actions.map(\.identifier)).count == actions.count)
    for action in actions {
      #expect(MainWindowToolbarAction(identifier: action.identifier) == action)
      #expect(MainWindowToolbarLayout.allowedItems.contains(action.identifier))
      #expect(NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil) != nil)
      #expect(OJDLocalized.string(action.labelKey) != action.labelKey)
      if let key = action.descriptionKey {
        #expect(OJDLocalized.string(key) != key)
        #expect(key != action.labelKey)
      }
    }
  }

  @Test
  @MainActor
  func theLibrarySearchFieldShowsItsLabelForVoiceOver() throws {
    let item = try #require(
      MainWindowToolbarLayout.makeItem(for: .searchLibrary) as? NSSearchToolbarItem
    )
    #expect(item.searchField.placeholderString == item.label)
  }

  @Test
  func onlyControllersHasASummaryLineWhileTheServiceIsUnavailable() {
    for area in MainWindowArea.allCases {
      #expect(MainWindowSummary.text(for: area, status: .loading).isEmpty)
    }
  }

  @Test
  func everyAreaSymbolExistsOnThisSystem() {
    for area in MainWindowArea.allCases {
      #expect(NSImage(systemSymbolName: area.symbolName, accessibilityDescription: nil) != nil)
    }
  }

  @Test
  func settingsPanesRunInToolbarOrder() {
    #expect(SettingsWindowPane.allCases == [.general, .notifications, .advanced])
  }
}

private final class MemoryAreaPersistence: MainWindowAreaPersistence {
  var area: MainWindowArea?
  func loadArea() -> MainWindowArea? { area }
  func saveArea(_ area: MainWindowArea) { self.area = area }
}
