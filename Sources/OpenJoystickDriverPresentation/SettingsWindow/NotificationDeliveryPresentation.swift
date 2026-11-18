#if canImport(AppKit) && canImport(SwiftUI)

  import OpenJoystickDriverKit

  /// What the Notifications pane says about delivery; while `needsAttention`, the pane offers the
  /// Notifications pane of System Settings.
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

    /// The text that says why notifications do not reach the user, or nil while they do.
    var status: String? {
      switch settings.authorization {
      case .denied:
        return OJDLocalized.string(
          SystemSettingsMessage.notificationsDenied.localizationKey()
        )
      case .notDetermined:
        return OJDLocalized.string("ui.settings.notifications.notificationPermissionRequired")
      case .checking: return nil
      case .allowed: break
      }
      switch (settings.alertStyle, settings.soundsEnabled) {
      case (.none, false):
        return OJDLocalized.string(
          SystemSettingsMessage.bannersAndSoundOff.localizationKey()
        )
      case (.none, _):
        return OJDLocalized.string(
          SystemSettingsMessage.bannersOff.localizationKey()
        )
      case (_, false):
        return OJDLocalized.string(
          SystemSettingsMessage.soundOff.localizationKey()
        )
      case (.banner, true), (.alert, true), (.unknown, _), (_, nil): return nil
      }
    }
  }

#endif
