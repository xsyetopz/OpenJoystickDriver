import OpenJoystickDriverKit

extension MainMenuModel {
  /// Returns the rows of `section` that show at `level`, without the separators a hidden item
  /// leaves at the start or the end of the menu or next to another separator.
  static func visibleEntries(
    of section: MainMenuSection,
    level: InterfaceLevel,
    developerToolsEnabled: Bool = false
  ) -> [MainMenuEntry] {
    var rows: [MainMenuEntry] = []
    for entry in section.entries {
      if let item = entry.item,
        !item.action.interfaceRowLevel.isShown(
          at: level,
          developerToolsEnabled: developerToolsEnabled
        )
      {
        continue
      }
      if entry == .separator, rows.isEmpty || rows.last == .separator { continue }
      rows.append(entry)
    }
    if rows.last == .separator { rows.removeLast() }
    return rows
  }
}
