#if canImport(AppKit)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UserNotifications

  extension RuntimeNotificationMonitor {

    func observe(_ snapshot: RuntimeNotificationSnapshot) {
      guard let previousSnapshot else {
        self.previousSnapshot = snapshot
        return
      }
      self.previousSnapshot = snapshot
      for event in RuntimeNotificationDiff.events(from: previousSnapshot, to: snapshot) {
        deliver(event)
      }
    }

    func deliver(_ event: RuntimeNotificationEvent) {
      switch event {
      case .controllerConnected(let name):
        guard preferenceIsEnabled(ApplicationPreferenceKeys.controllerNotifications) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerConnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerConnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .controllerDisconnected(let name):
        guard
          preferenceIsEnabled(
            ApplicationPreferenceKeys.controllerDisconnectedNotifications,
            fallbackKey: ApplicationPreferenceKeys.controllerNotifications
          )
        else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerDisconnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerDisconnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .activeProfileChanged(let previousName, let currentName):
        let preferenceKey =
          currentName == nil
          ? ApplicationPreferenceKeys.profileDeactivatedNotifications
          : ApplicationPreferenceKeys.profileNotifications
        let fallbackKey = currentName == nil ? ApplicationPreferenceKeys.profileNotifications : nil
        guard preferenceIsEnabled(preferenceKey, fallbackKey: fallbackKey) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.profileChanged"
          ),
          body: profileChangeBody(from: previousName, to: currentName),
          sound: notificationSoundIsEnabled
        )
      case .controllerNeedsAttention(let name):
        guard preferenceIsEnabled(ApplicationPreferenceKeys.controllerNotifications) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerNeedsAttention"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerNeedsAttentionBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      }
    }

    private var notificationSoundIsEnabled: Bool {
      defaults.object(forKey: ApplicationPreferenceKeys.notificationSounds) as? Bool ?? true
    }

    private func preferenceIsEnabled(_ key: String, fallbackKey: String? = nil) -> Bool {
      if let value = defaults.object(forKey: key) as? Bool { return value }
      return fallbackKey.map { defaults.bool(forKey: $0) } ?? false
    }

    private func profileChangeBody(from previousName: String?, to currentName: String?) -> String {
      switch (previousName, currentName) {
      case (.some(let previous), .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileSwitchedBody",
          previous,
          current
        )
      case (.none, .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileActivatedBody",
          current
        )
      case (.some(let previous), .none):
        return OJDLocalized.formatted(
          "notifications.profileDeactivatedBody",
          previous
        )
      case (.none, .none):
        return OJDLocalized.string("status.noActiveProfile")
      }
    }
  }

#endif
