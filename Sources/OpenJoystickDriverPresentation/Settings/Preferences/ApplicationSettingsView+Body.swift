#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension ApplicationSettingsView {

    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: OJDLocalized.string("settings.title", fallback: "Settings"))
            primarySettings(width: proxy.size.width - 48)

            notificationSettings
            updateSettings
            commandLineToolSettings

            if let errorMessage = preferences.errorMessage {
              HStack(alignment: .top, spacing: 8) {
                OJDSystemSymbol(
                  name: SemanticState.attention.presentation.symbolName,
                  fallback: OJDLocalized.string(
                    "common.needsAttention",
                    fallback: "Needs attention"
                  )
                ).foregroundColor(Color(SemanticState.attention.presentation.tone.color))
                Text(errorMessage).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if preferences.notificationAuthorization == .denied {
                  Button(
                    OJDLocalized.string("settings.openSystemSettings", fallback: "Open Settings")
                  ) { preferences.openNotificationSettings() }
                }
                Button(OJDLocalized.string("common.dismiss", fallback: "Dismiss")) {
                  preferences.dismissError()
                }
              }.padding(10).background(Color(NSColor.controlBackgroundColor)).cornerRadius(8)
            }
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.onAppear { preferences.refreshNotificationAuthorization() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in preferences.refreshNotificationAuthorization() }
    }

    @ViewBuilder
    private func primarySettings(width: CGFloat) -> some View {
      if width < 650 {
        VStack(alignment: .leading, spacing: 16) {
          generalSettings
          developerSettings
        }
      } else {
        HStack(alignment: .top, spacing: 16) {
          generalSettings
          developerSettings
        }
      }
    }

    private var generalSettings: some View {
      GroupBox {
        switchSetting(
          title: OJDLocalized.string("settings.startAtLogin", fallback: "Start at login"),
          description: OJDLocalized.string(
            "settings.startAtLoginDescription",
            fallback: "Open OpenJoystickDriver in the menu bar when you log in."
          ),
          isOn: Binding(
            get: { preferences.startAtLogin },
            set: { preferences.setStartAtLogin($0) }
          ),
          isEnabled: preferences.launchAtLoginIsAvailable
        ).padding(4).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.general", fallback: "General")).font(.headline)
      }.frame(maxWidth: .infinity)
    }

    private var notificationSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top, spacing: 24) {
            notificationEventGroup(
              title: OJDLocalized.string("settings.controllers", fallback: "Controllers"),
              firstTitle: OJDLocalized.string(
                "settings.controllerConnectedShort",
                fallback: "Connected"
              ),
              firstAccessibility: OJDLocalized.string(
                "settings.controllerNotifications",
                fallback: "Controller connected"
              ),
              firstIsOn: Binding(
                get: { preferences.controllerNotifications },
                set: { preferences.setControllerNotifications($0) }
              ),
              secondTitle: OJDLocalized.string(
                "settings.controllerDisconnectedShort",
                fallback: "Disconnected"
              ),
              secondAccessibility: OJDLocalized.string(
                "settings.controllerDisconnectedNotifications",
                fallback: "Controller disconnected"
              ),
              secondIsOn: Binding(
                get: { preferences.controllerDisconnectedNotifications },
                set: { preferences.setControllerDisconnectedNotifications($0) }
              )
            )
            notificationEventGroup(
              title: OJDLocalized.string("settings.profiles", fallback: "Profiles"),
              firstTitle: OJDLocalized.string(
                "settings.profileActivatedShort",
                fallback: "Activated or switched"
              ),
              firstAccessibility: OJDLocalized.string(
                "settings.profileNotifications",
                fallback: "Profile activated or switched"
              ),
              firstIsOn: Binding(
                get: { preferences.profileNotifications },
                set: { preferences.setProfileNotifications($0) }
              ),
              secondTitle: OJDLocalized.string(
                "settings.profileDeactivatedShort",
                fallback: "Deactivated"
              ),
              secondAccessibility: OJDLocalized.string(
                "settings.profileDeactivatedNotifications",
                fallback: "Profile deactivated"
              ),
              secondIsOn: Binding(
                get: { preferences.profileDeactivatedNotifications },
                set: { preferences.setProfileDeactivatedNotifications($0) }
              )
            )
            Spacer(minLength: 0)
          }
          Divider()
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(OJDLocalized.string("settings.notificationSounds", fallback: "Play a sound"))
              Text(notificationDeliveryStatus).font(.caption).foregroundColor(
                notificationDeliveryNeedsAttention
                  ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor)
              )
              if notificationDeliveryNeedsAttention {
                Button(
                  OJDLocalized.string(
                    "settings.openNotificationSettings",
                    fallback: "Open Notification Settings"
                  )
                ) { preferences.openNotificationSettings() }
              }
            }
            Spacer(minLength: 12)
            Toggle(
              OJDLocalized.string("settings.notificationSounds", fallback: "Play a sound"),
              isOn: Binding(
                get: { preferences.notificationSounds },
                set: { preferences.setNotificationSounds($0) }
              )
            ).toggleStyle(.switch).labelsHidden().ojdAccessibilityLabel(
              OJDLocalized.string("settings.notificationSounds", fallback: "Play a sound")
            )
            Button(
              OJDLocalized.string("settings.testNotification", fallback: "Send Test Notification")
            ) { preferences.sendTestNotification() }
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.notifications", fallback: "Notifications")).font(
          .headline
        )
      }.frame(maxWidth: .infinity)
    }

    private var notificationDeliveryNeedsAttention: Bool {
      guard preferences.notificationAuthorization == .allowed else { return false }
      return preferences.notificationSystemSettings.alertStyle == .none
        || preferences.notificationSystemSettings.soundsEnabled == false
    }

    private var notificationDeliveryStatus: String {
      guard preferences.notificationAuthorization == .allowed else {
        return OJDLocalized.string(
          "settings.notificationPermissionRequired",
          fallback: "Permission is required before notifications can be delivered."
        )
      }
      switch (
        preferences.notificationSystemSettings.alertStyle,
        preferences.notificationSystemSettings.soundsEnabled
      ) {
      case (.none, false):
        return OJDLocalized.string(
          "settings.notificationBannersAndSoundOff",
          fallback: "Banners and sounds are disabled in System Settings."
        )
      case (.none, _):
        return OJDLocalized.string(
          "settings.notificationBannersOffDetail",
          fallback: "Notification banners are disabled in System Settings."
        )
      case (_, false):
        return OJDLocalized.string(
          "settings.notificationSoundOffDetail",
          fallback: "Notification sounds are disabled in System Settings."
        )
      case (.banner, true), (.alert, true):
        return OJDLocalized.string(
          "settings.notificationDeliveryReady",
          fallback: "Banners, Notification Center, and sounds are enabled."
        )
      case (.unknown, _), (_, nil):
        return OJDLocalized.string(
          "settings.notificationDeliveryAllowed",
          fallback: "Notification delivery is allowed."
        )
      }
    }

    private var updateSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(updateStatusTitle).font(.body.weight(.medium))
              Text(updateStatusDetail).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
            Spacer()
            if case .available = preferences.updateState {
              Button(OJDLocalized.string("settings.viewUpdate", fallback: "View Update")) {
                preferences.openAvailableUpdate()
              }
            }
            Button(OJDLocalized.string("settings.checkUpdates", fallback: "Check Now")) {
              preferences.checkForUpdates()
            }.disabled(preferences.updateState == .checking)
          }
          Divider()
          HStack {
            Text(
              OJDLocalized.string(
                "settings.prereleaseUpdates",
                fallback: "Include prerelease updates"
              )
            )
            Spacer(minLength: 12)
            Toggle(
              OJDLocalized.string(
                "settings.prereleaseUpdates",
                fallback: "Include prerelease updates"
              ),
              isOn: Binding(
                get: { preferences.includePrereleaseUpdates },
                set: { preferences.setIncludePrereleaseUpdates($0) }
              )
            ).toggleStyle(.switch).labelsHidden().ojdAccessibilityLabel(
              OJDLocalized.string(
                "settings.prereleaseUpdates",
                fallback: "Include prerelease updates"
              )
            )
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.updates", fallback: "Updates")).font(.headline)
      }
    }

    private var developerSettings: some View {
      GroupBox {
        switchSetting(
          title: OJDLocalized.string(
            "settings.enableDeveloperTools",
            fallback: "Enable Developer Tools"
          ),
          description: OJDLocalized.string(
            "settings.developerToolsDescription",
            fallback: "Show controller input and USB packet tools."
          ),
          isOn: Binding(
            get: { preferences.developerToolsEnabled },
            set: { preferences.setDeveloperToolsEnabled($0) }
          )
        ).padding(4).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.developerTools", fallback: "Developer Tools")).font(
          .headline
        )
      }.frame(maxWidth: .infinity)
    }

    private func switchSetting(
      title: String,
      description: String,
      isOn: Binding<Bool>,
      isEnabled: Bool = true
    ) -> some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
          Text(description).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().disabled(!isEnabled)
          .ojdAccessibilityLabel(title)
      }
    }

    private func notificationEventGroup(
      title: String,
      firstTitle: String,
      firstAccessibility: String,
      firstIsOn: Binding<Bool>,
      secondTitle: String,
      secondAccessibility: String,
      secondIsOn: Binding<Bool>
    ) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Toggle(firstTitle, isOn: firstIsOn).toggleStyle(.checkbox).ojdAccessibilityLabel(
          firstAccessibility
        )
        Toggle(secondTitle, isOn: secondIsOn).toggleStyle(.checkbox).ojdAccessibilityLabel(
          secondAccessibility
        )
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

#endif
