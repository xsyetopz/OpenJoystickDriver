import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainMenuToolbarCommandTests {
  private func section(_ id: String) throws -> MainMenuSection {
    try #require(MainMenuModel.sections.first { $0.id == id })
  }

  @Test
  func everyToolbarActionHasAMenuCommand() throws {
    for action in MainWindowToolbarAction.allCases {
      let item = try #require(
        MainMenuModel.item(forToolbar: action),
        "\(action) has no menu command"
      )
      #expect(item.action == action.menuAction)
    }
  }

  @Test
  func newCommandsKeepTheToolbarTitleAndTheOthersReuseExistingItems() throws {
    var added = 0
    for action in MainWindowToolbarAction.allCases {
      let item = try #require(MainMenuModel.item(forToolbar: action))
      guard case .toolbar(let carried) = item.action else { continue }
      added += 1
      #expect(carried == action)
      #expect(item.titleKey == action.labelKey, "\(action) changes the toolbar item's title")
      #expect(item.keyEquivalent.isEmpty)
    }
    #expect(added == 14)
    #expect(MainWindowToolbarAction.importProfile.menuAction == .importProfile)
    #expect(MainWindowToolbarAction.exportProfile.menuAction == .exportProfile)
    #expect(MainWindowToolbarAction.installLibraryItem.menuAction == .installRecordOrMod)
    #expect(MainWindowToolbarAction.saveActivityLog.menuAction == .saveActivityLog)
    #expect(MainWindowToolbarAction.searchLibrary.menuAction == .find)
    #expect(MainWindowToolbarAction.activitySearch.menuAction == .find)
  }

  @Test
  func commandsAreEnabledWhenTheToolbarItemIs() throws {
    let item = try #require(MainMenuModel.item(forToolbar: .duplicateProfile))
    var state = MainMenuState(hasMainWindow: true)
    #expect(!MainMenuModel.isEnabled(item, state: state))
    state.enabledToolbarActions = [.duplicateProfile]
    #expect(MainMenuModel.isEnabled(item, state: state))
    let other = try #require(MainMenuModel.item(forToolbar: .deleteProfile))
    #expect(!MainMenuModel.isEnabled(other, state: state))
  }

  @Test
  func profileCommandsSitInTheProfileMenuAndActivityOnesInView() throws {
    #expect(
      try section("profile").items.map(\.action) == [
        .activateProfile, .deactivateProfile, .toolbar(.newProfile), .toolbar(.duplicateProfile),
        .toolbar(.deleteProfile), .toolbar(.validateProfileFile),
      ]
    )
    let view = try section("view").items.map(\.action)
    #expect(view.contains(.toolbar(.activityMode)))
    #expect(view.contains(.toolbar(.activityFilter)))
    #expect(view.contains(.toolbar(.runDiagnostics)))
  }

  @Test
  func findIsInTheEditMenuWithCommandF() throws {
    let find = try #require(try section("edit").items.first { $0.action == .find })
    #expect(find.keyEquivalent == "f")
    #expect(find.modifiers == [.command])
    #expect(find.titleKey == "ui.menu.edit.find")
    #expect(!MainMenuModel.isEnabled(find, state: MainMenuState(hasMainWindow: true)))
    #expect(
      MainMenuModel.isEnabled(
        find,
        state: MainMenuState(hasMainWindow: true, hasSearchFieldInView: true)
      )
    )
  }

  @Test
  func findTargetsTheSearchFieldOfTheListInView() {
    #expect(MainWindowArea.library.searchAction(activityMode: .log) == .searchLibrary)
    #expect(MainWindowArea.activity.searchAction(activityMode: .log) == .activitySearch)
    #expect(MainWindowArea.activity.searchAction(activityMode: .diagnostics) == nil)
    for area in [MainWindowArea.controllers, .profiles, .access] {
      #expect(area.searchAction(activityMode: .log) == nil)
    }
  }
}
