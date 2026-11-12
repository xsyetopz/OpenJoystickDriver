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
  private static func auditLevels() throws -> [String: String] {
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
      levels[cells[1]] = cells[cells.count - 3]
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
          ["C05", "C06", "C07", "C08", "C09", "C10", "C11", "C12", "C13", "C14", "C15", "C16"]
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
    let ids = (1...16).map { $0 < 10 ? "P0\($0)" : "P\($0)" }
    #expect(Set(rows.flatMap(\.auditIDs)) == Set(ids))
    #expect(
      rows.filter { $0.rowLevel == .advanced }.flatMap(\.auditIDs).sorted() == ["P12", "P14"]
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
