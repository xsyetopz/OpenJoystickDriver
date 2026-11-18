import OpenJoystickDriverKit

/// The level at which a row of a view shows: `docs/development/interface-audit.md` gives each
/// audited control one.
enum InterfaceRowLevel: String, Hashable {
  /// Shows at both levels.
  case simple
  /// Shows only in Advanced.
  case advanced
  /// Shows only in Advanced with the developer switch on.
  case developer

  /// Returns whether a row of this level shows.
  ///
  /// - Parameters:
  ///   - level: The interface level.
  ///   - developerToolsEnabled: Whether the developer switch is on.
  /// - Returns: Whether a row of this level shows.
  func isShown(at level: InterfaceLevel, developerToolsEnabled: Bool) -> Bool {
    switch self {
    case .simple: return true
    case .advanced: return level == .advanced
    case .developer: return level == .advanced && developerToolsEnabled
    }
  }
}

/// The rows of one view: a case for each part of the view the audit gives a level, so a test can
/// compare the list with the audit and the view hides a part with `ojdInterfaceRow(_:)`.
protocol InterfaceRow: CaseIterable, Hashable {
  /// The audit IDs of the controls the row draws; a row of a split control names the ID too.
  var auditIDs: [String] { get }
  /// The level of the row.
  var rowLevel: InterfaceRowLevel { get }
}

extension InterfaceRow {
  /// Returns the rows that show.
  ///
  /// - Parameters:
  ///   - level: The interface level.
  ///   - developerToolsEnabled: Whether the developer switch is on.
  /// - Returns: The rows that show.
  static func shown(at level: InterfaceLevel, developerToolsEnabled: Bool) -> [Self] {
    allCases.filter {
      $0.rowLevel.isShown(at: level, developerToolsEnabled: developerToolsEnabled)
    }
  }
}
