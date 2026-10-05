#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  enum ApplicationPreferenceKeys {
    static let controllerNotifications = "OpenJoystickDriver.notifications.controllers"
    static let controllerDisconnectedNotifications =
      "OpenJoystickDriver.notifications.controllerDisconnected"
    static let profileNotifications = "OpenJoystickDriver.notifications.profiles"
    static let profileDeactivatedNotifications =
      "OpenJoystickDriver.notifications.profileDeactivated"
    static let notificationSounds = ApplicationSettingKey.notificationSounds.defaultsKey ?? ""
    static let includePrereleaseUpdates =
      ApplicationSettingKey.includePrereleaseUpdates.defaultsKey ?? ""
    static let developerTools = ApplicationSettingKey.developerTools.defaultsKey ?? ""
  }

  protocol ApplicationUpdateChecking: Sendable {
    func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState
  }

  extension UpdateChecker: ApplicationUpdateChecking {}

  @MainActor
  final class SettingsPreferencesModel: ObservableObject {
    @Published
    private(set) var startAtLogin: Bool
    @Published
    private(set) var controllerNotifications: Bool
    @Published
    private(set) var controllerDisconnectedNotifications: Bool
    @Published
    private(set) var profileNotifications: Bool
    @Published
    private(set) var profileDeactivatedNotifications: Bool
    @Published
    private(set) var notificationSounds: Bool
    @Published
    private(set) var notificationAuthorization: RuntimeNotificationAuthorizationState
    @Published
    private(set) var notificationSystemSettings: RuntimeNotificationSettings
    @Published
    private(set) var includePrereleaseUpdates: Bool
    @Published
    private(set) var developerToolsEnabled: Bool
    @Published
    private(set) var updateState: UpdateCheckState = .idle
    @Published
    private(set) var errorMessage: String?

    let launchAtLoginIsAvailable: Bool

    private let defaults: UserDefaults
    private let launchAtLogin: any LaunchAtLoginControlling
    private let notificationAuthorizationController: any NotificationAuthorizationControlling
    /// Counts authorization reads. The controller answers off the main actor, so a refresh that
    /// started before a newer read can finish after it; its result is then stale and dropped.
    private var notificationAuthorizationReads = 0
    private let updateChecker: any ApplicationUpdateChecking
    private let notificationDelivery: any RuntimeNotificationDelivering

    init(
      defaults: UserDefaults = .standard,
      launchAtLogin: any LaunchAtLoginControlling = SystemLaunchAtLoginController(),
      notificationAuthorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController(),
      updateChecker: any ApplicationUpdateChecking = UpdateChecker(),
      notificationDelivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      self.defaults = defaults
      self.launchAtLogin = launchAtLogin
      self.notificationAuthorizationController = notificationAuthorization
      self.updateChecker = updateChecker
      self.notificationDelivery = notificationDelivery
      self.launchAtLoginIsAvailable = launchAtLogin.isAvailable
      self.startAtLogin = launchAtLogin.isEnabled
      self.notificationAuthorization = .checking
      self.notificationSystemSettings = .authorizationOnly(.checking)
      let controllerNotifications = defaults.bool(
        forKey: ApplicationPreferenceKeys.controllerNotifications
      )
      self.controllerNotifications = controllerNotifications
      self.controllerDisconnectedNotifications = Self.preference(
        ApplicationPreferenceKeys.controllerDisconnectedNotifications,
        defaults: defaults,
        fallback: controllerNotifications
      )
      let profileNotifications = defaults.bool(
        forKey: ApplicationPreferenceKeys.profileNotifications
      )
      self.profileNotifications = profileNotifications
      self.profileDeactivatedNotifications = Self.preference(
        ApplicationPreferenceKeys.profileDeactivatedNotifications,
        defaults: defaults,
        fallback: profileNotifications
      )
      self.notificationSounds = Self.preference(
        ApplicationPreferenceKeys.notificationSounds,
        defaults: defaults,
        fallback: true
      )
      self.includePrereleaseUpdates = defaults.bool(
        forKey: ApplicationPreferenceKeys.includePrereleaseUpdates
      )
      self.developerToolsEnabled = defaults.bool(forKey: ApplicationPreferenceKeys.developerTools)
      refreshNotificationAuthorization()
    }

    func setStartAtLogin(_ enabled: Bool) {
      do {
        try launchAtLogin.setEnabled(enabled)
        startAtLogin = launchAtLogin.isEnabled
        if enabled && !startAtLogin {
          errorMessage = OJDLocalized.string(
            "settings.startAtLoginApprovalRequired"
          )
        } else {
          errorMessage = nil
        }
      } catch {
        startAtLogin = launchAtLogin.isEnabled
        errorMessage = error.localizedDescription
      }
    }

    func setControllerNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllers)
    }

    func setProfileNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profiles)
    }

    func setControllerDisconnectedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllerDisconnections)
    }

    func setProfileDeactivatedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profileDeactivations)
    }

    func setNotificationSounds(_ enabled: Bool) {
      defaults.set(enabled, forKey: ApplicationPreferenceKeys.notificationSounds)
      notificationSounds = enabled
    }

    func sendTestNotification() { setNotificationPreference(true, preference: .test) }

    func setIncludePrereleaseUpdates(_ enabled: Bool) {
      defaults.set(enabled, forKey: ApplicationPreferenceKeys.includePrereleaseUpdates)
      includePrereleaseUpdates = enabled
    }

    func setDeveloperToolsEnabled(_ enabled: Bool) {
      defaults.set(enabled, forKey: ApplicationPreferenceKeys.developerTools)
      developerToolsEnabled = enabled
    }

    func checkForUpdates() {
      guard updateState != .checking else { return }
      updateState = .checking
      let includePrereleases = includePrereleaseUpdates
      Task { @MainActor [weak self, updateChecker] in
        let state = await updateChecker.check(
          currentVersion: ApplicationVersion.current,
          includePrereleases: includePrereleases
        )
        self?.updateState = state
      }
    }

    func openAvailableUpdate() {
      guard case .available(let info) = updateState else { return }
      NSWorkspace.shared.open(info.htmlURL)
    }

    func openNotificationSettings() { notificationAuthorizationController.openSystemSettings() }

    func dismissError() { errorMessage = nil }

    func refreshNotificationAuthorization() {
      notificationAuthorizationReads += 1
      let read = notificationAuthorizationReads
      Task { [weak self, notificationAuthorizationController] in
        let settings = await notificationAuthorizationController.settings()
        guard let self, read == self.notificationAuthorizationReads else { return }
        let state = settings.authorization
        self.notificationAuthorization = state
        self.notificationSystemSettings = settings
        if state == .denied {
          self.defaults.set(false, forKey: ApplicationPreferenceKeys.controllerNotifications)
          self.defaults.set(
            false,
            forKey: ApplicationPreferenceKeys.controllerDisconnectedNotifications
          )
          self.defaults.set(false, forKey: ApplicationPreferenceKeys.profileNotifications)
          self.defaults.set(
            false,
            forKey: ApplicationPreferenceKeys.profileDeactivatedNotifications
          )
          self.controllerNotifications = false
          self.controllerDisconnectedNotifications = false
          self.profileNotifications = false
          self.profileDeactivatedNotifications = false
        }
      }
    }

    private func setNotificationPreference(_ enabled: Bool, preference: NotificationPreference) {
      let key = preference.defaultsKey
      guard enabled else {
        defaults.set(false, forKey: key)
        update(preference, enabled: false)
        errorMessage = nil
        return
      }
      notificationAuthorizationReads += 1
      Task { [weak self, notificationAuthorizationController] in
        let state = await notificationAuthorizationController.state()
        guard let self else { return }
        self.notificationAuthorization = state
        switch state {
        case .allowed:
          self.acceptNotificationPreference(preference, key: key)
          self.refreshNotificationAuthorization()
        case .notDetermined, .checking: self.requestNotificationAuthorization(preference, key: key)
        case .denied: self.rejectNotificationPreference(preference, key: key, errorDescription: nil)
        }
      }
    }

    private func requestNotificationAuthorization(_ preference: NotificationPreference, key: String)
    {
      notificationAuthorizationReads += 1
      Task { [weak self, notificationAuthorizationController] in
        let (state, errorDescription) = await notificationAuthorizationController.request()
        guard let self else { return }
        self.notificationAuthorization = state
        if state == .allowed && errorDescription == nil {
          self.acceptNotificationPreference(preference, key: key)
        } else {
          self.rejectNotificationPreference(
            preference,
            key: key,
            errorDescription: errorDescription
          )
        }
      }
    }

    private func acceptNotificationPreference(_ preference: NotificationPreference, key: String) {
      if preference == .test {
        notificationDelivery.deliver(
          title: OJDLocalized.string(
            "notifications.testTitle"
          ),
          body: OJDLocalized.string(
            "notifications.testBody"
          ),
          sound: notificationSounds
        )
      } else {
        defaults.set(true, forKey: key)
        update(preference, enabled: true)
      }
      errorMessage = nil
    }

    private func rejectNotificationPreference(
      _ preference: NotificationPreference,
      key: String,
      errorDescription: String?
    ) {
      if preference != .test {
        defaults.set(false, forKey: key)
        update(preference, enabled: false)
      }
      errorMessage =
        errorDescription
        ?? OJDLocalized.string(
          "settings.notificationsDenied"
        )
    }

    private func update(_ preference: NotificationPreference, enabled: Bool) {
      switch preference {
      case .controllers: controllerNotifications = enabled
      case .controllerDisconnections: controllerDisconnectedNotifications = enabled
      case .profiles: profileNotifications = enabled
      case .profileDeactivations: profileDeactivatedNotifications = enabled
      case .test: break
      }
    }

    private static func preference(_ key: String, defaults: UserDefaults, fallback: Bool) -> Bool {
      defaults.object(forKey: key) as? Bool ?? fallback
    }
  }

  private enum NotificationPreference: Sendable, Equatable {
    case controllers
    case controllerDisconnections
    case profiles
    case profileDeactivations
    case test

    var defaultsKey: String {
      switch self {
      case .controllers: return ApplicationPreferenceKeys.controllerNotifications
      case .controllerDisconnections:
        return ApplicationPreferenceKeys.controllerDisconnectedNotifications
      case .profiles: return ApplicationPreferenceKeys.profileNotifications
      case .profileDeactivations: return ApplicationPreferenceKeys.profileDeactivatedNotifications
      case .test: return ""
      }
    }
  }

#endif
