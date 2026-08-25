#if canImport(AppKit)

  import AppKit
  import Foundation
  import UserNotifications

  enum RuntimeNotificationAuthorizationState: Equatable, Sendable {
    case checking
    case notDetermined
    case denied
    case allowed
  }

  enum RuntimeNotificationAlertStyle: Equatable, Sendable {
    case none
    case banner
    case alert
    case unknown
  }

  struct RuntimeNotificationSettings: Equatable, Sendable {
    let authorization: RuntimeNotificationAuthorizationState
    let alertStyle: RuntimeNotificationAlertStyle
    let soundsEnabled: Bool?

    static func authorizationOnly(_ authorization: RuntimeNotificationAuthorizationState) -> Self {
      Self(authorization: authorization, alertStyle: .unknown, soundsEnabled: nil)
    }
  }

  protocol NotificationAuthorizationControlling: Sendable {
    func state(completion: @escaping @Sendable (RuntimeNotificationAuthorizationState) -> Void)
    func request(
      completion: @escaping @Sendable (RuntimeNotificationAuthorizationState, String?) -> Void
    )
    func settings(completion: @escaping @Sendable (RuntimeNotificationSettings) -> Void)
    @MainActor func openSystemSettings()
  }

  extension NotificationAuthorizationControlling {
    func settings(completion: @escaping @Sendable (RuntimeNotificationSettings) -> Void) {
      state { completion(.authorizationOnly($0)) }
    }
  }

  struct SystemNotificationAuthorizationController: NotificationAuthorizationControlling {
    func state(completion: @escaping @Sendable (RuntimeNotificationAuthorizationState) -> Void) {
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        completion(Self.state(for: settings.authorizationStatus))
      }
    }

    func request(
      completion: @escaping @Sendable (RuntimeNotificationAuthorizationState, String?) -> Void
    ) {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
        authorized,
        error in completion(authorized ? .allowed : .denied, error?.localizedDescription)
      }
    }

    func settings(completion: @escaping @Sendable (RuntimeNotificationSettings) -> Void) {
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        completion(
          RuntimeNotificationSettings(
            authorization: Self.state(for: settings.authorizationStatus),
            alertStyle: Self.alertStyle(for: settings.alertStyle),
            soundsEnabled: settings.soundSetting == .enabled
          )
        )
      }
    }

    @MainActor func openSystemSettings() {
      let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.openjoystickdriver.app"
      let notificationsPane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
      if #available(macOS 13.0, *),
        let url = URL(string: "\(notificationsPane)?id=\(bundleIdentifier)"),
        NSWorkspace.shared.open(url)
      {
        return
      }
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
        NSWorkspace.shared.open(url)
      }
    }

    private static func state(for status: UNAuthorizationStatus)
      -> RuntimeNotificationAuthorizationState
    {
      switch status {
      case .notDetermined: return .notDetermined
      case .denied: return .denied
      case .authorized, .provisional, .ephemeral: return .allowed
      @unknown default: return .denied
      }
    }

    private static func alertStyle(for style: UNAlertStyle) -> RuntimeNotificationAlertStyle {
      switch style {
      case .none: return .none
      case .banner: return .banner
      case .alert: return .alert
      @unknown default: return .unknown
      }
    }
  }

  @MainActor final class NotificationPermissionModel: ObservableObject {
    @Published private(set) var state: RuntimeNotificationAuthorizationState = .checking
    @Published private(set) var settings = RuntimeNotificationSettings.authorizationOnly(.checking)
    @Published private(set) var errorMessage: String?

    private let authorization: any NotificationAuthorizationControlling

    init(
      authorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController()
    ) { self.authorization = authorization }

    func refresh() {
      authorization.settings { [weak self] settings in
        DispatchQueue.main.async { [weak self] in
          self?.settings = settings
          self?.state = settings.authorization
        }
      }
    }

    func requestOrOpenSettings() {
      if state == .denied
        || (state == .allowed && (settings.alertStyle == .none || settings.soundsEnabled == false))
      {
        authorization.openSystemSettings()
        return
      }
      authorization.request { [weak self] state, errorMessage in
        DispatchQueue.main.async { [weak self] in
          self?.state = state
          self?.errorMessage = errorMessage
          self?.refresh()
        }
      }
    }
  }

  struct RuntimeNotificationSnapshot: Equatable {
    let controllers: [String: String]?
    let activeProfiles: [String: String]?

    @MainActor init(viewModel: RuntimeViewModel) {
      switch viewModel.statusState {
      case .available(let status):
        controllers = Dictionary(
          uniqueKeysWithValues: status.devices.map { ($0.runtimeIdentifier, $0.name) }
        )
      case .loading, .unavailable, .error: controllers = nil
      }

      switch viewModel.remappingState {
      case .available(let snapshot):
        activeProfiles = Dictionary(
          uniqueKeysWithValues: snapshot.activeProfiles.map {
            ("\($0.vendorID):\($0.productID)", $0.profileName)
          }
        )
      case .loading, .unavailable, .error: activeProfiles = nil
      }
    }

    init(controllers: [String: String]?, activeProfiles: [String: String]?) {
      self.controllers = controllers
      self.activeProfiles = activeProfiles
    }
  }

  enum RuntimeNotificationEvent: Equatable {
    case controllerConnected(String)
    case controllerDisconnected(String)
    case activeProfileChanged(from: String?, to: String?)
  }

  enum RuntimeNotificationDiff {
    static func events(
      from previous: RuntimeNotificationSnapshot,
      to current: RuntimeNotificationSnapshot
    ) -> [RuntimeNotificationEvent] {
      var events: [RuntimeNotificationEvent] = []
      if let previousControllers = previous.controllers,
        let currentControllers = current.controllers
      {
        for identifier in currentControllers.keys.sorted()
        where previousControllers[identifier] == nil {
          if let name = currentControllers[identifier] { events.append(.controllerConnected(name)) }
        }
        for identifier in previousControllers.keys.sorted()
        where currentControllers[identifier] == nil {
          if let name = previousControllers[identifier] {
            events.append(.controllerDisconnected(name))
          }
        }
      }
      if let previousProfiles = previous.activeProfiles,
        let currentProfiles = current.activeProfiles
      {
        for device in Set(previousProfiles.keys).union(currentProfiles.keys).sorted()
        where previousProfiles[device] != currentProfiles[device] {
          events.append(
            .activeProfileChanged(from: previousProfiles[device], to: currentProfiles[device])
          )
        }
      }
      return events
    }
  }

  protocol RuntimeNotificationDelivering { func deliver(title: String, body: String, sound: Bool) }

  struct SystemRuntimeNotificationDelivery: RuntimeNotificationDelivering {
    func deliver(title: String, body: String, sound: Bool) {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = sound ? .default : nil
      content.threadIdentifier = "OpenJoystickDriver.runtime"
      let request = UNNotificationRequest(
        identifier: "OpenJoystickDriver.\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request) { error in
        if let error { print("[Notifications] Delivery failed: \(error.localizedDescription)") }
      }
    }
  }

  final class RuntimeNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static var foregroundPresentationOptions: UNNotificationPresentationOptions {
      if #available(macOS 11.0, *) { return [.banner, .sound] }
      return [.alert, .sound]
    }

    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler(Self.foregroundPresentationOptions) }
  }

  @MainActor final class RuntimeNotificationMonitor {
    private let defaults: UserDefaults
    private let delivery: any RuntimeNotificationDelivering
    private var previousSnapshot: RuntimeNotificationSnapshot?

    init(
      defaults: UserDefaults = .standard,
      delivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      self.defaults = defaults
      self.delivery = delivery
    }

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

    private func deliver(_ event: RuntimeNotificationEvent) {
      switch event {
      case .controllerConnected(let name):
        guard preferenceIsEnabled(ApplicationPreferenceKeys.controllerNotifications) else { return }
        delivery.deliver(
          title: OJDLocalized.string(
            "notifications.controllerConnected",
            fallback: "Controller connected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerConnectedBody",
            fallback: "%@ is ready to use.",
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
            "notifications.controllerDisconnected",
            fallback: "Controller disconnected"
          ),
          body: OJDLocalized.formatted(
            "notifications.controllerDisconnectedBody",
            fallback: "%@ is no longer connected.",
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
            "notifications.profileChanged",
            fallback: "Active profile changed"
          ),
          body: profileChangeBody(from: previousName, to: currentName),
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
          fallback: "%@ → %@",
          previous,
          current
        )
      case (.none, .some(let current)):
        return OJDLocalized.formatted(
          "notifications.profileActivatedBody",
          fallback: "%@ is now active.",
          current
        )
      case (.some(let previous), .none):
        return OJDLocalized.formatted(
          "notifications.profileDeactivatedBody",
          fallback: "%@ is no longer active.",
          previous
        )
      case (.none, .none):
        return OJDLocalized.string("status.noActiveProfile", fallback: "No active profile")
      }
    }
  }

#endif
