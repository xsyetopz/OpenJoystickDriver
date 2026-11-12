import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// The main menu against the Level column of `docs/development/interface-audit.md`.
struct MenuInterfaceRowsTests {
  /// The audit ID whose level a command takes: the toolbar item it repeats, S05 for the error
  /// code lookup, or the split rows M08 and M17 for the Activity Log item.
  private static func auditID(of action: MainMenuAction) -> String? {
    switch action {
    case .toolbar(let toolbar): return toolbarIDs[toolbar]
    case .installRecordOrMod: return "T08"
    case .saveActivityLog: return "T19"
    case .explainErrorCode, .showActivityLog: return "S05"
    default: return nil
    }
  }

  private static let toolbarIDs: [MainWindowToolbarAction: String] = [
    .validateLibraryItem: "T09", .testLibraryRecord: "T10", .removeLibraryItem: "T11",
    .grantProgram: "T13", .createToken: "T14", .activityMode: "T15", .activityFilter: "T16",
    .copyActivityLog: "T18", .showActivityLogInFinder: "T20", .runDiagnostics: "T21",
    .newProfile: "T02", .importProfile: "T03", .validateProfileFile: "T04",
    .duplicateProfile: "T05", .exportProfile: "T06", .deleteProfile: "T07",
    .installLibraryItem: "T08", .searchLibrary: "T12", .activitySearch: "T17",
    .saveActivityLog: "T19",
  ]

  @Test
  func everyMenuItemLevelMatchesTheAudit() throws {
    let audit = try InterfaceRowAuditTests.auditLevels()
    for id in (10...17).map({ "M\($0)" }) + ["M08"] {
      #expect(audit[id] == "Simple", "\(id)")
    }
    for item in MainMenuModel.allItems {
      guard let id = Self.auditID(of: item.action) else {
        #expect(item.action.interfaceRowLevel == .simple, "\(item.id)")
        continue
      }
      let level = try #require(audit[id])
      #expect(item.action.interfaceRowLevel.rawValue == level.lowercased(), "\(item.id) \(id)")
    }
  }

  @Test
  func simpleItemsAreASubsetOfAdvancedAndHideTheHiddenControls() {
    for section in MainMenuModel.sections {
      let simple = Set(
        MainMenuModel.visibleEntries(of: section, level: .simple).compactMap(\.item?.id)
      )
      let advanced = Set(
        MainMenuModel.visibleEntries(of: section, level: .advanced).compactMap(\.item?.id)
      )
      let developer = Set(
        MainMenuModel.visibleEntries(
          of: section,
          level: .advanced,
          developerToolsEnabled: true
        ).compactMap(\.item?.id)
      )
      #expect(simple.isSubset(of: advanced), "\(section.id)")
      #expect(advanced.isSubset(of: developer), "\(section.id)")
      #expect(developer == Set(section.items.map(\.id)), "\(section.id)")
    }
    let simpleActions = Set(
      MainMenuModel.sections.flatMap {
        MainMenuModel.visibleEntries(of: $0, level: .simple).compactMap(\.item?.action)
      }
    )
    for hidden: MainMenuAction in [
      .showActivityLog, .explainErrorCode, .installRecordOrMod, .saveActivityLog,
      .toolbar(.grantProgram), .toolbar(.createToken), .toolbar(.runDiagnostics),
      .toolbar(.removeLibraryItem), .toolbar(.copyActivityLog),
    ] {
      #expect(!simpleActions.contains(hidden), "\(hidden)")
    }
    for kept: MainMenuAction in [
      .saveSupportReport, .copySupportReport, .importProfile, .exportProfile,
      .toolbar(.newProfile), .showArea(.library), .setInterfaceLevel(.advanced),
    ] {
      #expect(simpleActions.contains(kept), "\(kept)")
    }
  }

  @Test
  func developerCommandsNeedTheDeveloperSwitch() throws {
    let file = try #require(MainMenuModel.sections.first { $0.id == "file" })
    func actions(_ developer: Bool) -> [MainMenuAction] {
      MainMenuModel.visibleEntries(
        of: file,
        level: .advanced,
        developerToolsEnabled: developer
      ).compactMap(\.item?.action)
    }
    #expect(!actions(false).contains(.toolbar(.grantProgram)))
    #expect(actions(false).contains(.installRecordOrMod))
    #expect(actions(true).contains(.toolbar(.createToken)))
  }

  @Test(arguments: InterfaceLevel.allCases)
  func hiddenItemsLeaveNoStraySeparators(level: InterfaceLevel) {
    for section in MainMenuModel.sections {
      let entries = MainMenuModel.visibleEntries(of: section, level: level)
      #expect(entries.first != .separator, "\(section.id)")
      #expect(entries.last != .separator, "\(section.id)")
      for pair in zip(entries, entries.dropFirst()) {
        #expect(!(pair.0 == .separator && pair.1 == .separator), "\(section.id)")
      }
    }
  }
}
