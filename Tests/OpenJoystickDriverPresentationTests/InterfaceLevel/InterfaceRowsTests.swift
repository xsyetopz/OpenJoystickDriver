import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct InterfaceRowLevelTests {
  @Test(
    arguments: [
      (InterfaceRowLevel.simple, InterfaceLevel.simple, false, true),
      (.simple, .simple, true, true),
      (.simple, .advanced, false, true),
      (.advanced, .simple, false, false),
      (.advanced, .simple, true, false),
      (.advanced, .advanced, false, true),
      (.developer, .simple, true, false),
      (.developer, .advanced, false, false),
      (.developer, .advanced, true, true),
    ]
  )
  func rowLevelShowsByLevelAndDeveloperSwitch(
    row: InterfaceRowLevel,
    level: InterfaceLevel,
    developerToolsEnabled: Bool,
    expected: Bool
  ) {
    #expect(row.isShown(at: level, developerToolsEnabled: developerToolsEnabled) == expected)
  }
}

/// The rows of a view against the Level column of `docs/development/interface-audit.md`.
struct InterfaceRowAuditTests {
  /// The audit's level of each control ID, read from the confirmed list.
  static func auditLevels() throws -> [String: String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(
      contentsOf: root.appendingPathComponent("docs/development/interface-audit.md"),
      encoding: .utf8
    )
    var levels: [String: String] = [:]
    for line in text.split(separator: "\n") where line.hasPrefix("| ") {
      let cells = line.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
      let isControl =
        cells.count > 3
        && cells[1].range(of: #"^[A-Z]\d{2}$"#, options: .regularExpression) != nil
      guard isControl else { continue }
      // The 12.12 comparison table repeats S01 to S24 later with text after the level; the first
      // row with a real level, in section 2, is the one with the Level column.
      let level = cells[cells.count - 3]
      if levels[cells[1]] == nil, InterfaceRowLevel(rawValue: level.lowercased()) != nil {
        levels[cells[1]] = level
      }
    }
    return levels
  }

  /// A split row names the part that belongs to another level in its basis cell.
  private static let splitParts: [String: Set<InterfaceRowLevel>] = ["C06": [.advanced]]

  private func expectMatchesAudit<Row: InterfaceRow>(_ rows: [Row]) throws {
    let audit = try Self.auditLevels()
    var covered: [String: Set<InterfaceRowLevel>] = [:]
    for row in rows {
      for id in row.auditIDs { covered[id, default: []].insert(row.rowLevel) }
    }
    for (id, levels) in covered {
      let level = try #require(audit[id], "\(id) is not in the audit")
      let allowed = Set([level.lowercased()].compactMap(InterfaceRowLevel.init(rawValue:)))
        .union(Self.splitParts[id] ?? [])
      #expect(levels == allowed, "\(id): rows \(levels), audit \(allowed)")
    }
  }

  @Test
  func controllerDetailRowsMatchTheAuditLevels() throws {
    let rows = ControllerDetailRow.allCases
    try expectMatchesAudit(rows)
    #expect(
      Set(rows.flatMap(\.auditIDs))
        == Set(
          (5...16).map { $0 < 10 ? "C0\($0)" : "C\($0)" } + ["C30", "C31", "C32"]
        )
    )
  }

  @Test
  func inputTestRowsMatchTheAuditLevels() throws {
    let rows = InputTestRow.allCases
    try expectMatchesAudit(rows)
    #expect(
      Set(rows.flatMap(\.auditIDs)) == Set(["I01", "I02", "I03", "I04", "I05", "I06", "I07"])
    )
  }

  @Test
  func profilesRowsMatchTheAuditLevels() throws {
    let rows = ProfilesRow.allCases
    try expectMatchesAudit(rows)
    let ids = Set((18...20).map { "C\($0)" } + (8...24).map { $0 < 10 ? "S0\($0)" : "S\($0)" })
    #expect(Set(rows.flatMap(\.auditIDs)) == ids)
  }

  @Test
  func profilesSimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(ProfilesRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(ProfilesRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isSubset(of: advanced))
    #expect(simple != advanced)
  }

  @Test
  func accessRowsMatchTheAuditLevels() throws {
    let rows = AccessRow.allCases
    try expectMatchesAudit(rows)
    #expect(
      Set(rows.flatMap(\.auditIDs))
        == Set(["C24", "C25", "C26", "C27", "S01", "S02", "S03"])
    )
  }

  @Test
  func activityRowsMatchTheAuditLevels() throws {
    let rows = ActivityRow.allCases
    try expectMatchesAudit(rows)
    #expect(Set(rows.flatMap(\.auditIDs)) == Set(["C28", "C29", "S05"]))
  }

  @Test
  func libraryRowsMatchTheAuditLevels() throws {
    let rows = LibraryRow.allCases
    try expectMatchesAudit(rows)
    #expect(Set(rows.flatMap(\.auditIDs)) == Set(["C21", "C22", "C23", "S04"]))
  }

  @Test
  func accessSimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(AccessRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(AccessRow.shown(at: .advanced, developerToolsEnabled: false))
    let developer = Set(AccessRow.shown(at: .advanced, developerToolsEnabled: true))
    #expect(simple == [.permissions])
    #expect(simple.isSubset(of: advanced))
    #expect(advanced.isSubset(of: developer))
    #expect(developer == Set(AccessRow.allCases))
  }

  @Test
  func activitySimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(ActivityRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(ActivityRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isEmpty)
    #expect(simple.isSubset(of: advanced))
    #expect(advanced == Set(ActivityRow.allCases))
  }

  @Test
  func librarySimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(LibraryRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(LibraryRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isEmpty)
    #expect(simple.isSubset(of: advanced))
    #expect(advanced == Set(LibraryRow.allCases))
  }

  @Test
  func toolbarItemsAreGatedByTheAuditLevels() throws {
    let audit = try Self.auditLevels()
    let gated: [(MainWindowToolbarAction, String)] = [
      (.newProfile, "T02"), (.importProfile, "T03"), (.validateProfileFile, "T04"),
      (.duplicateProfile, "T05"), (.exportProfile, "T06"), (.deleteProfile, "T07"),
      (.installLibraryItem, "T08"), (.validateLibraryItem, "T09"), (.testLibraryRecord, "T10"),
      (.removeLibraryItem, "T11"), (.searchLibrary, "T12"), (.grantProgram, "T13"),
      (.createToken, "T14"), (.activityMode, "T15"), (.activityFilter, "T16"),
      (.activitySearch, "T17"), (.copyActivityLog, "T18"), (.saveActivityLog, "T19"),
      (.showActivityLogInFinder, "T20"), (.runDiagnostics, "T21"),
    ]
    #expect(Set(gated.map(\.0)).union([.convertProfile]) == Set(MainWindowToolbarAction.allCases))
    #expect(try #require(audit["T01"]) == "Simple")
    for (action, id) in gated {
      let level = try #require(audit[id])
      #expect(action.interfaceRowLevel.rawValue == level.lowercased(), "\(id)")
    }
    let simple = MainWindowArea.access.toolbarActions(
      activityMode: .log,
      level: .simple,
      developerToolsEnabled: true
    )
    #expect(simple.isEmpty)
    #expect(
      MainWindowArea.access.toolbarActions(
        activityMode: .log,
        level: .advanced,
        developerToolsEnabled: false
      ).isEmpty
    )
    #expect(
      MainWindowArea.access.toolbarActions(
        activityMode: .log,
        level: .advanced,
        developerToolsEnabled: true
      ) == [.grantProgram, .createToken]
    )
    #expect(
      !MainWindowArea.activity.toolbarActions(
        activityMode: .diagnostics,
        level: .simple,
        developerToolsEnabled: false
      ).contains(.runDiagnostics)
    )
    #expect(
      MainWindowArea.activity.toolbarActions(
        activityMode: .diagnostics,
        level: .advanced,
        developerToolsEnabled: false
      ).contains(.runDiagnostics)
    )
  }

  @Test
  func controllerDetailSimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(ControllerDetailRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(ControllerDetailRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isSubset(of: advanced))
    #expect(simple != advanced)
  }

  @Test
  func inputTestSimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(InputTestRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(InputTestRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isSubset(of: advanced))
  }

  @Test
  func settingsRowsMatchTheAuditLevels() throws {
    let rows = SettingsRow.allCases
    try expectMatchesAudit(rows)
    let ids = (1...18).map { $0 < 10 ? "P0\($0)" : "P\($0)" }
    #expect(Set(rows.flatMap(\.auditIDs)) == Set(ids))
    #expect(
      rows.filter { $0.rowLevel == .advanced }.flatMap(\.auditIDs).sorted()
        == ["P12", "P14", "P17", "P18"]
    )
    #expect(rows.filter { $0.rowLevel == .developer }.flatMap(\.auditIDs) == ["P15"])
  }

  @Test
  func settingsSimpleRowsAreASubsetOfAdvanced() {
    let simple = Set(SettingsRow.shown(at: .simple, developerToolsEnabled: true))
    let advanced = Set(SettingsRow.shown(at: .advanced, developerToolsEnabled: false))
    #expect(simple.isSubset(of: advanced))
    #expect(simple != advanced)
    #expect(simple.contains(.interfacePicker))
    #expect(!simple.contains(.commandLineTool))
    #expect(!simple.contains(.developerToolsSwitch))
  }

  @Test
  func developerRowsShowOnlyInAdvancedWithTheSwitch() {
    #expect(
      !ControllerDetailRow.shown(at: .advanced, developerToolsEnabled: false)
        .contains(.developerActions)
    )
    #expect(
      !ControllerDetailRow.shown(at: .simple, developerToolsEnabled: true)
        .contains(.developerActions)
    )
    #expect(
      ControllerDetailRow.shown(at: .advanced, developerToolsEnabled: true)
        .contains(.developerActions)
    )
  }
}
