#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Per-event notifications, the notification permission and Send Test Notification.
  struct NotificationsPaneView: View {
    /// The notification switches and the permission state.
    @ObservedObject
    var preferences: SettingsPreferencesModel

    /// The Notifications form: the settings error, if any, and the switches for each event.
    var body: some View {
      Form {
        SettingsErrorSection(preferences: preferences)
        Section(OJDLocalized.string("ui.settings.general.controllers")) {
          eventToggle(
            "ui.settings.notifications.controllerConnectedOrAttention",
            "ui.settings.notifications.controllerNotifications",
            \.controllerNotifications,
            preferences.setControllerNotifications
          )
          eventToggle(
            "ui.settings.notifications.controllerDisconnectedShort",
            "ui.settings.notifications.controllerDisconnectedNotifications",
            \.controllerDisconnectedNotifications,
            preferences.setControllerDisconnectedNotifications
          )
        }
        Section(OJDLocalized.string("ui.settings.general.profiles")) {
          eventToggle(
            "ui.settings.notifications.profileActivatedShort",
            "ui.settings.notifications.profileNotifications",
            \.profileNotifications,
            preferences.setProfileNotifications
          )
          eventToggle(
            "ui.settings.notifications.profileDeactivatedShort",
            "ui.settings.notifications.profileDeactivatedNotifications",
            \.profileDeactivatedNotifications,
            preferences.setProfileDeactivatedNotifications
          )
        }
        Section {
          Toggle(
            OJDLocalized.string("ui.settings.notifications.notificationSounds"),
            isOn: Binding(
              get: { preferences.notificationSounds },
              set: { preferences.setNotificationSounds($0) }
            )
          )
        }
        Section { deliveryRow }
      }.ojdGroupedForm()
    }

    /// The notification delivery status, with Open Notification Settings while macOS hides banners
    /// or sounds and the Send Test Notification button.
    private var deliveryRow: some View {
      let system = preferences.notificationSystemSettings
      let delivery = NotificationDeliveryPresentation(
        settings: RuntimeNotificationSettings(
          authorization: preferences.notificationAuthorization,
          alertStyle: system.alertStyle,
          soundsEnabled: system.soundsEnabled
        )
      )
      return HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.small) {
        Text(delivery.status).foregroundColor(
          delivery.needsAttention
            ? Color(NSColor.systemOrange) : Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 12)
        if delivery.needsAttention {
          Button(OJDLocalized.string("ui.settings.general.openNotificationSettings")) {
            preferences.openNotificationSettings()
          }
        }
        Button(OJDLocalized.string("ui.settings.notifications.testNotification")) {
          preferences.sendTestNotification()
        }
      }
    }

    /// Returns the switch of one notification event, with the VoiceOver label `accessibilityKey`.
    private func eventToggle(
      _ titleKey: String,
      _ accessibilityKey: String,
      _ value: KeyPath<SettingsPreferencesModel, Bool>,
      _ set: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> some View {
      Toggle(
        OJDLocalized.string(titleKey),
        isOn: Binding(get: { preferences[keyPath: value] }, set: set)
      ).ojdAccessibilityLabel(OJDLocalized.string(accessibilityKey))
    }
  }

#endif
