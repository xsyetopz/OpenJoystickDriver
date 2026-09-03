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
    static let notificationSounds = "OpenJoystickDriver.notifications.sounds"
    static let includePrereleaseUpdates = "OpenJoystickDriver.updates.includePrereleases"
    static let developerTools = "OpenJoystickDriver.developerTools.enabled"
  }

  protocol ApplicationUpdateChecking: Sendable {
    func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState
  }

  extension UpdateChecker: ApplicationUpdateChecking {}

  @MainActor final class SettingsPreferencesModel: ObservableObject {
    @Published private(set) var startAtLogin: Bool
    @Published private(set) var controllerNotifications: Bool
    @Published private(set) var controllerDisconnectedNotifications: Bool
    @Published private(set) var profileNotifications: Bool
    @Published private(set) var profileDeactivatedNotifications: Bool
    @Published private(set) var notificationSounds: Bool
    @Published private(set) var notificationAuthorization: RuntimeNotificationAuthorizationState
    @Published private(set) var notificationSystemSettings: RuntimeNotificationSettings
    @Published private(set) var includePrereleaseUpdates: Bool
    @Published private(set) var developerToolsEnabled: Bool
    @Published private(set) var updateState: UpdateCheckState = .idle
    @Published private(set) var errorMessage: String?

    let launchAtLoginIsAvailable: Bool

    private let defaults: UserDefaults
    private let launchAtLogin: any LaunchAtLoginControlling
    private let notificationAuthorizationController: any NotificationAuthorizationControlling
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
            "settings.startAtLoginApprovalRequired",
            fallback: "Allow OpenJoystickDriver in System Settings > General > Login Items."
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
      notificationAuthorizationController.settings { [weak self] settings in
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
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
    }

    private func setNotificationPreference(_ enabled: Bool, preference: NotificationPreference) {
      let key = preference.defaultsKey
      guard enabled else {
        defaults.set(false, forKey: key)
        update(preference, enabled: false)
        errorMessage = nil
        return
      }
      notificationAuthorizationController.state { [weak self] state in
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.notificationAuthorization = state
          switch state {
          case .allowed:
            self.acceptNotificationPreference(preference, key: key)
            self.refreshNotificationAuthorization()
          case .notDetermined, .checking:
            self.requestNotificationAuthorization(preference, key: key)
          case .denied:
            self.rejectNotificationPreference(preference, key: key, errorDescription: nil)
          }
        }
      }
    }

    private func requestNotificationAuthorization(_ preference: NotificationPreference, key: String)
    {
      notificationAuthorizationController.request { [weak self] state, errorDescription in
        DispatchQueue.main.async { [weak self] in
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
    }

    private func acceptNotificationPreference(_ preference: NotificationPreference, key: String) {
      if preference == .test {
        notificationDelivery.deliver(
          title: OJDLocalized.string(
            "notifications.testTitle",
            fallback: "Notifications are ready"
          ),
          body: OJDLocalized.string(
            "notifications.testBody",
            fallback: "OpenJoystickDriver can notify you about controller and profile activity."
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
          "settings.notificationsDenied",
          fallback: "Notifications are disabled for OpenJoystickDriver in System Settings."
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

  struct ApplicationSettingsView: View {
    @ObservedObject private var preferences: SettingsPreferencesModel

    init(preferences: SettingsPreferencesModel = SettingsPreferencesModel()) {
      self.preferences = preferences
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PageHeader(title: OJDLocalized.string("settings.title", fallback: "Settings"))
          HStack(alignment: .top, spacing: 16) {
            generalSettings
            notificationSettings
          }

          updateSettings
          developerSettings

          if let errorMessage = preferences.errorMessage {
            HStack(alignment: .top, spacing: 8) {
              OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
                Color(NSColor.systemOrange)
              )
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
      }.onAppear { preferences.refreshNotificationAuthorization() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in preferences.refreshNotificationAuthorization() }
    }

    private var generalSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            OJDLocalized.string("settings.startAtLogin", fallback: "Start at login"),
            isOn: Binding(
              get: { preferences.startAtLogin },
              set: { preferences.setStartAtLogin($0) }
            )
          ).disabled(!preferences.launchAtLoginIsAvailable)
          Text(
            OJDLocalized.string(
              "settings.startAtLoginDescription",
              fallback: "Start OpenJoystickDriver quietly in the menu bar after login."
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(4).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
      } label: {
        Text(OJDLocalized.string("settings.general", fallback: "General")).font(.headline)
      }.frame(maxWidth: .infinity)
    }

    private var notificationSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            OJDLocalized.string(
              "settings.controllerNotifications",
              fallback: "Controller connected"
            ),
            isOn: Binding(
              get: { preferences.controllerNotifications },
              set: { preferences.setControllerNotifications($0) }
            )
          )
          Toggle(
            OJDLocalized.string(
              "settings.controllerDisconnectedNotifications",
              fallback: "Controller disconnected"
            ),
            isOn: Binding(
              get: { preferences.controllerDisconnectedNotifications },
              set: { preferences.setControllerDisconnectedNotifications($0) }
            )
          )
          Toggle(
            OJDLocalized.string(
              "settings.profileNotifications",
              fallback: "Profile activated or switched"
            ),
            isOn: Binding(
              get: { preferences.profileNotifications },
              set: { preferences.setProfileNotifications($0) }
            )
          )
          Toggle(
            OJDLocalized.string(
              "settings.profileDeactivatedNotifications",
              fallback: "Profile deactivated"
            ),
            isOn: Binding(
              get: { preferences.profileDeactivatedNotifications },
              set: { preferences.setProfileDeactivatedNotifications($0) }
            )
          )
          Divider()
          Toggle(
            OJDLocalized.string("settings.notificationSounds", fallback: "Play a sound"),
            isOn: Binding(
              get: { preferences.notificationSounds },
              set: { preferences.setNotificationSounds($0) }
            )
          )
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
          Button(
            OJDLocalized.string("settings.testNotification", fallback: "Send Test Notification")
          ) { preferences.sendTestNotification() }
        }.padding(4).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
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
          Toggle(
            OJDLocalized.string(
              "settings.prereleaseUpdates",
              fallback: "Include prerelease updates"
            ),
            isOn: Binding(
              get: { preferences.includePrereleaseUpdates },
              set: { preferences.setIncludePrereleaseUpdates($0) }
            )
          )
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.updates", fallback: "Updates")).font(.headline)
      }
    }

    private var developerSettings: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            OJDLocalized.string(
              "settings.enableDeveloperTools",
              fallback: "Enable Developer Tools"
            ),
            isOn: Binding(
              get: { preferences.developerToolsEnabled },
              set: { preferences.setDeveloperToolsEnabled($0) }
            )
          )
          Text(
            OJDLocalized.string(
              "settings.developerToolsDescription",
              fallback: "Show controller input and USB packet tools."
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("settings.developerTools", fallback: "Developer Tools")).font(
          .headline
        )
      }
    }

    private var updateStatusTitle: String {
      switch preferences.updateState {
      case .idle: return OJDLocalized.string("settings.updateIdle", fallback: "Check for updates")
      case .checking: return OJDLocalized.string("settings.updateChecking", fallback: "Checking…")
      case .upToDate: return OJDLocalized.string("settings.upToDate", fallback: "Up to date")
      case .available:
        return OJDLocalized.string("settings.updateAvailable", fallback: "Update available")
      case .failed:
        return OJDLocalized.string("settings.updateFailed", fallback: "Update check failed")
      }
    }

    private var updateStatusDetail: String {
      switch preferences.updateState {
      case .idle:
        return OJDLocalized.formatted(
          "settings.currentVersion",
          fallback: "Current version: %@",
          ApplicationVersion.current
        )
      case .checking:
        return OJDLocalized.string("settings.contactingGitHub", fallback: "Contacting GitHub…")
      case .upToDate(let tag): return tag
      case .available(let info): return info.tagName
      case .failed(let message): return message
      }
    }
  }

#endif
