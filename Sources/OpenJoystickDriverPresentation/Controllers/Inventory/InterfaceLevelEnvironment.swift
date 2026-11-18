#if canImport(SwiftUI)

  import OpenJoystickDriverKit
  import SwiftUI

  // The keys are spelled out instead of using `@Entry`: that macro's plugin ships only with Xcode,
  // and the Command Line Tools build has to compile this module too.
  private enum InterfaceLevelKey: EnvironmentKey {
    static var defaultValue: InterfaceLevel { .default }
  }

  private enum DeveloperToolsEnabledKey: EnvironmentKey {
    static var defaultValue: Bool { false }
  }

  private enum PreferencesKey: EnvironmentKey {
    static var defaultValue: SettingsPreferencesModel? { nil }
  }

  extension EnvironmentValues {
    /// How much of the interface shows; the main window sets it from the Settings preference.
    var ojdInterfaceLevel: InterfaceLevel {
      get { self[InterfaceLevelKey.self] }
      set { self[InterfaceLevelKey.self] = newValue }
    }

    /// Whether the developer switch is on; a developer row also needs Advanced.
    var ojdDeveloperToolsEnabled: Bool {
      get { self[DeveloperToolsEnabledKey.self] }
      set { self[DeveloperToolsEnabledKey.self] = newValue }
    }

    /// The preferences that store the interface level, so a view can switch it; the main window
    /// sets it.
    var ojdPreferences: SettingsPreferencesModel? {
      get { self[PreferencesKey.self] }
      set { self[PreferencesKey.self] = newValue }
    }
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
