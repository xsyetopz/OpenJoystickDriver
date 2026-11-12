#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Launch at login, the menu bar item, the Dock icon and update checks.
  struct GeneralPaneView: View {
    /// The switches of General and the update state.
    @ObservedObject
    var preferences: SettingsPreferencesModel

    /// The General form: the settings error, if any, and the switches.
    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        Section {
          SettingsSwitchRow(
            title: OJDLocalized.string("ui.settings.general.startAtLogin"),
            isOn: Binding(
              get: { preferences.startAtLogin },
              set: { preferences.setStartAtLogin($0) }
            ),
            isEnabled: preferences.launchAtLoginIsAvailable,
            disabledReason: preferences.startAtLoginUnavailableReason
          ).ojdInterfaceRow(SettingsRow.startAtLogin)
          SettingsBesideError(preferences: preferences, origin: .loginItem)
          SettingsSwitchRow(
            title: OJDLocalized.string("ui.settings.general.showInMenuBar"),
            isOn: Binding(
              get: { preferences.showInMenuBar },
              set: { preferences.setShowInMenuBar($0) }
            ),
            isEnabled: !preferences.showInMenuBarIsLocked,
            disabledReason: OJDLocalized.string(
              "platform.macos.ui.settings.general.entryPointRequired"
            )
          ).ojdInterfaceRow(SettingsRow.showInMenuBar)
          SettingsSwitchRow(
            title: OJDLocalized.string("platform.macos.ui.settings.general.showInDock"),
            description: OJDLocalized.string(
              "platform.macos.ui.settings.general.showInDockDescription"
            ),
            isOn: Binding(
              get: { preferences.showInDock },
              set: { preferences.setShowInDock($0) }
            ),
            isEnabled: !preferences.showInDockIsLocked,
            disabledReason: OJDLocalized.string(
              "platform.macos.ui.settings.general.entryPointRequired"
            )
          ).ojdInterfaceRow(SettingsRow.showInDock)
          PauseShortcutRow(preferences: preferences).ojdInterfaceRow(SettingsRow.pauseShortcut)
          IdleDisconnectRow(preferences: preferences).ojdInterfaceRow(SettingsRow.idleDisconnect)
          Picker(
            OJDLocalized.string("ui.settings.general.interface"),
            selection: Binding(
              get: { preferences.interfaceLevel },
              set: { preferences.setInterfaceLevel($0) }
            )
          ) {
            Text(OJDLocalized.string("ui.settings.general.interfaceSimple"))
              .tag(InterfaceLevel.simple)
            Text(OJDLocalized.string("ui.settings.general.interfaceAdvanced"))
              .tag(InterfaceLevel.advanced)
          }
          .ojdInterfaceRow(SettingsRow.interfacePicker)
        }
        updates
      }.ojdGroupedForm().ojdSettingsInterfaceLevel(preferences)
    }

    /// The Updates section: the check state, View Update while a release is available, Check for
    /// Updates and the automatic and prerelease switches.
    private var updates: some View {
      Section(OJDLocalized.string("ui.settings.general.updates")) {
        HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
          VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
            HStack(spacing: OJDSpacing.small) {
              indicator(status.indicator)
              Text(status.title)
            }
            if let latestRelease = status.latestRelease {
              Text(latestRelease).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
          }
          Spacer(minLength: 8)
          Text(status.version).foregroundColor(Color(NSColor.secondaryLabelColor))
          if case .available = preferences.updateState {
            Button(OJDLocalized.string("ui.settings.general.viewUpdate")) {
              preferences.openAvailableUpdate()
            }
          }
          Button(OJDLocalized.string("ui.settings.general.checkUpdates")) {
            preferences.checkForUpdates()
          }.disabled(preferences.updateState == .checking)
        }.ojdInterfaceRow(SettingsRow.version)
        SettingsSwitchRow(
          title: OJDLocalized.string("ui.settings.general.checkUpdatesAutomatically"),
          isOn: Binding(
            get: { preferences.checkUpdatesAutomatically },
            set: { preferences.setCheckUpdatesAutomatically($0) }
          )
        ).ojdInterfaceRow(SettingsRow.checkUpdatesAutomatically)
        Toggle(
          OJDLocalized.string("ui.settings.general.prereleaseUpdates"),
          isOn: Binding(
            get: { preferences.includePrereleaseUpdates },
            set: { preferences.setIncludePrereleaseUpdates($0) }
          )
        ).ojdInterfaceRow(SettingsRow.prereleaseUpdates)
      }
    }

    /// Returns the indicator at the start of the update status label.
    @ViewBuilder
    private func indicator(_ indicator: UpdateStatusPresentation.Indicator) -> some View {
      switch indicator {
      case .none: EmptyView()
      case .progress: ProgressView().controlSize(.small).accessibilityHidden(true)
      case .symbol(let name, let tone):
        Image(systemName: name).foregroundColor(Color(Self.color(of: tone)))
          .accessibilityHidden(true)
      }
    }

    /// Returns the system color of a tone.
    private static func color(of tone: UpdateStatusPresentation.Tone) -> NSColor {
      switch tone {
      case .positive: return SemanticState.healthy.presentation.tone.color
      case .attention: return SemanticState.attention.presentation.tone.color
      case .informational: return NSColor.controlAccentColor
      case .failure: return SemanticState.failure.presentation.tone.color
      }
    }

    /// The update status that the section shows for the update check state.
    private var status: UpdateStatusPresentation {
      UpdateStatusPresentation(
        state: preferences.updateState,
        runningVersion: ApplicationVersion.current
      )
    }
  }

#endif
