#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// A titled switch with a one-line description below it; while the switch is disabled and has
  /// a `disabledReason`, the reason follows the description as a second line and is the switch's
  /// tooltip.
  struct SettingsSwitchRow: View {
    /// The title of the switch.
    let title: String
    /// The line below the switch.
    let description: String
    /// Whether the switch is on.
    let isOn: Binding<Bool>
    /// Whether the switch can be changed.
    var isEnabled = true
    /// The reason the switch is disabled, or nil for none.
    var disabledReason: String?

    /// The reason to show: the disabled reason while the switch is disabled, otherwise nil.
    var lockReason: String? { isEnabled ? nil : disabledReason }

    /// The toggle with its description and, while it is locked, the reason.
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Toggle(title, isOn: isOn).disabled(!isEnabled).help(lockReason ?? "")
        footnote(description)
        if let lockReason { footnote(lockReason) }
      }
    }

    /// Returns a line of secondary text.
    private func footnote(_ text: String) -> some View {
      Text(text).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
        horizontal: false,
        vertical: true
      )
    }
  }

  /// The inline error of the preferences model as a form section, with the notification
  /// permission shortcut; it is empty while there is no error.
  struct SettingsErrorSection: View {
    /// The preferences model whose error shows.
    @ObservedObject
    var preferences: SettingsPreferencesModel

    /// The error message in a section; nothing while no error exists.
    var body: some View {
      if let errorMessage = preferences.errorMessage
        ?? preferences.settingsFileError?.localizedDescription
      {
        Section {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            OJDSystemSymbol(
              name: SemanticState.attention.presentation.symbolName,
              fallback: OJDLocalized.string("status.needsAttention")
            ).foregroundColor(Color(SemanticState.attention.presentation.tone.color))
            Text(errorMessage).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if preferences.notificationAuthorization == .denied {
              Button(OJDLocalized.string("ui.settings.general.openSystemSettings")) {
                preferences.openNotificationSettings()
              }
            }
            if preferences.settingsFileError != nil {
              Button(
                OJDLocalized.string("platform.macos.ui.settings.advanced.unreadableShowInFinder")
              ) {
                preferences.showSettingsFileInFinder()
              }
              Button(OJDLocalized.string("ui.settings.advanced.unreadableResetSettings")) {
                preferences.resetSettings()
              }
            }
            if preferences.settingsFileError == nil {
              Button(OJDLocalized.string("action.dismiss")) { preferences.dismissError() }
            }
          }
        }
      }
    }
  }

#endif
