#if canImport(AppKit) && canImport(SwiftUI)

  import OpenJoystickDriverKit

  // While `needsAttention`, the pane offers the Notifications pane of System Settings.
  struct NotificationDeliveryPresentation: Equatable {
    /// What macOS allows the app to do with notifications.
    let settings: RuntimeNotificationSettings

    /// Whether macOS has denied notifications, or allows them but shows no banner or plays no
    /// sound.
    var needsAttention: Bool {
      switch settings.authorization {
      case .denied: return true
      case .allowed: return settings.alertStyle == .none || settings.soundsEnabled == false
      case .checking, .notDetermined: return false
      }
    }

    /// The text that says whether notifications reach the user.
    var status: String {
      switch settings.authorization {
      case .denied:
        return OJDLocalized.string("platform.macos.ui.settings.notifications.notificationsDenied")
      case .checking, .notDetermined:
        return OJDLocalized.string("ui.settings.notifications.notificationPermissionRequired")
      case .allowed: break
      }
      switch (settings.alertStyle, settings.soundsEnabled) {
      case (.none, false):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationBannersAndSoundOff"
        )
      case (.none, _):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationBannersOffDetail"
        )
      case (_, false):
        return OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationSoundOffDetail"
        )
      case (.banner, true), (.alert, true):
        return OJDLocalized.string("ui.settings.notifications.notificationDeliveryReady")
      case (.unknown, _), (_, nil):
        return OJDLocalized.string("ui.settings.notifications.notificationDeliveryAllowed")
      }
    }
  }

#endif
