#if canImport(SwiftUI)

  import OpenJoystickDriverKit
  import SwiftUI

  extension EnvironmentValues {
    /// How much of the interface shows; the main window sets it from the Settings preference.
    @Entry
    var ojdInterfaceLevel = InterfaceLevel.default
    /// Whether the developer switch is on; a developer row also needs Advanced.
    @Entry
    var ojdDeveloperToolsEnabled = false
  }

  /// Hides a view when its row is not shown at the environment's level.
  private struct InterfaceRowModifier<Row: InterfaceRow>: ViewModifier {
    let row: Row
    @Environment(\.ojdInterfaceLevel)
    private var level
    @Environment(\.ojdDeveloperToolsEnabled)
    private var developerToolsEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
      if row.rowLevel.isShown(at: level, developerToolsEnabled: developerToolsEnabled) {
        content
      }
    }
  }

  extension View {
    /// Shows the view only when `row` is shown at the interface level; the level hides and changes
    /// no behavior.
    ///
    /// - Parameter row: The row of the view's list that the view draws.
    /// - Returns: The view, hidden when the level does not show `row`.
    func ojdInterfaceRow<Row: InterfaceRow>(_ row: Row) -> some View {
      modifier(InterfaceRowModifier(row: row))
    }
  }

#endif
