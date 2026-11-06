#if canImport(AppKit)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UserNotifications

  extension RuntimeNotificationMonitor {

    /// Compares `snapshot` with the previous one and delivers a notification for each change.
    ///
    /// The first snapshot only sets the baseline. No notification is delivered while the settings
    /// file cannot be read.
    func observe(_ snapshot: RuntimeNotificationSnapshot) {
      guard let previousSnapshot else {
        self.previousSnapshot = snapshot
        return
      }
      self.previousSnapshot = snapshot
      let events = RuntimeNotificationDiff.events(from: previousSnapshot, to: snapshot)
      guard !events.isEmpty else { return }
      // Notification preferences and sounds have defaults, but the defaults are not the user's
      // choice while the settings file can't be read, so no event is delivered.
      do { _ = try settings.load() } catch {
        SettingsSkipLog.write(
          feature: "\(events.count) notification(s)",
          file: settings.userFileURL.path,
          error: error
        )
        return
      }
      for event in events { deliver(event) }
    }

    /// Delivers the notification for `event` when its preference is on.
    ///
    /// Controller Needs Attention follows the controller connected preference.
    func deliver(_ event: RuntimeNotificationEvent) {
      switch event {
      case .controllerConnected(let name):
        guard preferenceIsEnabled(.notifyControllerConnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notify.controllerConnected"
          ),
          body: OJDLocalized.formatted(
            "notify.controllerConnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .controllerDisconnected(let name):
        guard preferenceIsEnabled(.notifyControllerDisconnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notify.controllerDisconnected"
          ),
          body: OJDLocalized.formatted(
            "notify.controllerDisconnectedBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      case .activeProfileChanged(let previousName, let currentName):
        let preferenceKey: ApplicationSettingKey =
          currentName == nil ? .notifyProfileDeactivated : .notifyProfileActivated
        guard preferenceIsEnabled(preferenceKey) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notify.profileChanged"
          ),
          body: profileChangeBody(from: previousName, to: currentName),
          sound: notificationSoundIsEnabled
        )
      case .controllerNeedsAttention(let name):
        guard preferenceIsEnabled(.notifyControllerConnected) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notify.controllerNeedsAttention"
          ),
          body: OJDLocalized.formatted(
            "notify.controllerNeedsAttentionBody",
            name
          ),
          sound: notificationSoundIsEnabled
        )
      }
    }

    /// Whether notification sounds are enabled.
    private var notificationSoundIsEnabled: Bool { preferenceIsEnabled(.notifySounds) }

    /// Returns whether the preference `key` is on.
    ///
    /// A settings file that cannot be read is logged with its path, and the preference counts as
    /// off, so the notification is not delivered on a default.
    private func preferenceIsEnabled(_ key: ApplicationSettingKey) -> Bool {
      do { return try settings.value(of: key) } catch {
        SettingsSkipLog.write(
          feature: key.rawValue,
          file: settings.userFileURL.path,
          error: error
        )
        return false
      }
    }

    /// Returns the notification text for a change from `previousName` to `currentName`, which is
    /// nil for no active profile.
    private func profileChangeBody(from previousName: String?, to currentName: String?) -> String {
      switch (previousName, currentName) {
      case (.some(let previous), .some(let current)):
        return OJDLocalized.formatted(
          "notify.profileSwitchedBody",
          previous,
          current
        )
      case (.none, .some(let current)):
        return OJDLocalized.formatted(
          "notify.profileActivatedBody",
          current
        )
      case (.some(let previous), .none):
        return OJDLocalized.formatted(
          "notify.profileDeactivatedBody",
          previous
        )
      case (.none, .none):
        return OJDLocalized.string("status.noActiveProfile")
      }
    }
  }

#endif
