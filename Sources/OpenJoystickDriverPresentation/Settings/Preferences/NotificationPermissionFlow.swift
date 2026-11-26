#if canImport(AppKit) && canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  /// The notification switch of one event.
  enum NotificationPreference: Sendable, Equatable {
    /// A controller connects.
    case controllers
    /// A controller disconnects.
    case controllerDisconnections
    /// A profile activates.
    case profiles
    /// A profile deactivates.
    case profileDeactivations

    /// The setting that stores the preference.
    var settingKey: ApplicationSettingKey {
      switch self {
      case .controllers: return .notifyControllerConnected
      case .controllerDisconnections: return .notifyControllerDisconnected
      case .profiles: return .notifyProfileActivated
      case .profileDeactivations: return .notifyProfileDeactivated
      }
    }
  }

  /// Reads and requests the macOS notification permission for the notification switches.
  ///
  /// The flow owns the authorization reads and hands every change of the settings state to its
  /// ``Host``, so the owner keeps publishing and storing the values.
  @MainActor
  final class NotificationPermissionFlow {
    /// The owner's operations that the flow calls.
    struct Host {
      /// Stores `values` in the user settings file and returns whether it succeeded.
      let persist: @MainActor ([ApplicationSettingKey: Bool]) -> Bool
      /// Shows the state of the macOS permission.
      let setAuthorization: @MainActor (RuntimeNotificationAuthorizationState) -> Void
      /// Shows what macOS allows the app to do with notifications.
      let setSystemSettings: @MainActor (RuntimeNotificationSettings) -> Void
      /// Sets the switch of a preference.
      let setPreference: @MainActor (NotificationPreference, Bool) -> Void
      /// Shows the error text, or hides the error for nil.
      let setErrorMessage: @MainActor (String?) -> Void
      /// Whether notifications play a sound.
      let soundsEnabled: @MainActor () -> Bool
    }

    /// Reads and requests the notification permission.
    private let controller: any NotificationAuthorizationControlling
    /// Posts the test notification.
    private let delivery: any RuntimeNotificationDelivering
    /// The owner's operations.
    private let host: Host
    /// Counts authorization reads.
    ///
    /// The controller answers off the main actor, so a refresh that started before a newer read can
    /// finish after it; its result is then stale and dropped.
    private var reads = 0

    /// Creates a flow over `controller` that posts the test notification through `delivery`.
    init(
      controller: any NotificationAuthorizationControlling,
      delivery: any RuntimeNotificationDelivering,
      host: Host
    ) {
      self.controller = controller
      self.delivery = delivery
      self.host = host
    }

    /// Opens the notification settings of the app in System Settings.
    func openSystemSettings() { controller.openSystemSettings() }

    /// Turns a notification preference on or off; turning it on reads the macOS notification
    /// permission and requests it when it is undecided.
    func setPreference(_ enabled: Bool, preference: NotificationPreference) {
      guard enabled else {
        guard persist(preference, false) else { return }
        host.setPreference(preference, false)
        host.setErrorMessage(nil)
        return
      }
      reads += 1
      Task { [weak self, controller] in
        let state = await controller.state()
        guard let self else { return }
        host.setAuthorization(state)
        switch state {
        case .allowed:
          accept(preference)
          refresh()
        case .notDetermined, .checking: request(preference)
        case .denied: reject(preference, errorDescription: nil)
        }
      }
    }

    /// Reads the notification permission.
    ///
    /// While macOS denies it, the four event notifications are turned off.
    func refresh() {
      reads += 1
      let read = reads
      Task { [weak self, controller] in
        let systemSettings = await controller.settings()
        guard let self, read == reads else { return }
        let state = systemSettings.authorization
        host.setAuthorization(state)
        host.setSystemSettings(systemSettings)
        if state == .denied {
          let notifications: [ApplicationSettingKey] = [
            .notifyControllerConnected, .notifyControllerDisconnected, .notifyProfileActivated,
            .notifyProfileDeactivated,
          ]
          guard host.persist(Dictionary(uniqueKeysWithValues: notifications.map { ($0, false) }))
          else { return }
          host.setPreference(.controllers, false)
          host.setPreference(.controllerDisconnections, false)
          host.setPreference(.profiles, false)
          host.setPreference(.profileDeactivations, false)
        }
      }
    }

    /// Delivers the test notification, asking the system for permission first when it is not
    /// decided.
    ///
    /// A delivery the system rejects, or one with no notification center, is `failed`.
    func showTestNotification() async -> TestNotificationOutcome {
      reads += 1
      var state = await controller.state()
      host.setAuthorization(state)
      if state == .notDetermined || state == .checking {
        reads += 1
        let (requested, errorDescription) = await controller.request()
        state = requested
        host.setAuthorization(requested)
        if let errorDescription { return .failed(errorDescription) }
      }
      guard state == .allowed else { return .denied }
      do {
        try await delivery.deliverAwaitingSystem(
          title: OJDLocalized.string("notify.testTitle"),
          body: OJDLocalized.string("notify.testBody"),
          sound: host.soundsEnabled()
        )
      } catch { return .failed(error.localizedDescription) }
      refresh()
      return .shown
    }

    /// Asks macOS for the notification permission, then keeps `preference` on or turns it off.
    private func request(_ preference: NotificationPreference) {
      reads += 1
      Task { [weak self, controller] in
        let (state, errorDescription) = await controller.request()
        guard let self else { return }
        host.setAuthorization(state)
        if state == .allowed, errorDescription == nil {
          accept(preference)
        } else {
          reject(preference, errorDescription: errorDescription)
        }
      }
    }

    /// Stores `preference` as on and clears the error.
    private func accept(_ preference: NotificationPreference) {
      guard persist(preference, true) else { return }
      host.setPreference(preference, true)
      host.setErrorMessage(nil)
    }

    /// Stores `preference` as off and shows `errorDescription`, or the text for denied
    /// notifications when it is nil.
    private func reject(_ preference: NotificationPreference, errorDescription: String?) {
      if persist(preference, false) {
        host.setPreference(preference, false)
      }
      host.setErrorMessage(
        errorDescription
          ?? OJDLocalized.string(SystemSettingsMessage.notificationsDenied.localizationKey())
      )
    }

    /// Stores the setting of `preference` and returns whether it succeeded.
    private func persist(_ preference: NotificationPreference, _ value: Bool) -> Bool {
      host.persist([preference.settingKey: value])
    }
  }

#endif
