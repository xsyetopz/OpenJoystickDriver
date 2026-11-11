#if canImport(AppKit)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UserNotifications

  /// The notification center, or nil outside an app bundle, where
  /// `UNUserNotificationCenter.current()` raises an assertion instead of returning.
  var bundledNotificationCenter: UNUserNotificationCenter? {
    Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
  }

  /// Whether macOS lets the app post notifications.
  enum RuntimeNotificationAuthorizationState: Equatable, Sendable {
    /// The answer has not been read yet.
    case checking
    /// The user has not been asked.
    case notDetermined
    /// The user refused, or the process has no app bundle.
    case denied
    /// Notifications are allowed.
    case allowed
  }

  /// How macOS shows the app's notifications.
  enum RuntimeNotificationAlertStyle: Equatable, Sendable {
    /// No visible notification.
    case none
    /// A banner that disappears by itself.
    case banner
    /// An alert that stays until the user answers.
    case alert
    /// The style could not be read.
    case unknown
  }

  /// What macOS allows the app to do with notifications.
  struct RuntimeNotificationSettings: Equatable, Sendable {
    /// Whether notifications are allowed.
    let authorization: RuntimeNotificationAuthorizationState
    /// How a notification appears.
    let alertStyle: RuntimeNotificationAlertStyle
    /// Whether sounds are enabled, or nil when it was not read.
    let soundsEnabled: Bool?

    /// Returns settings that hold only `authorization`, with an unknown style and unread sounds.
    static func authorizationOnly(_ authorization: RuntimeNotificationAuthorizationState) -> Self {
      Self(authorization: authorization, alertStyle: .unknown, soundsEnabled: nil)
    }
  }

  /// Reads and requests the app's notification authorization.
  protocol NotificationAuthorizationControlling: Sendable {
    /// Returns the current authorization state.
    func state() async -> RuntimeNotificationAuthorizationState
    /// Requests authorization and returns the resulting state with an optional error description.
    func request() async -> (RuntimeNotificationAuthorizationState, String?)
    /// Returns the authorization state with the alert style and the sound setting.
    func settings() async -> RuntimeNotificationSettings
    /// Opens the notification settings of the app in System Settings.
    @MainActor
    func openSystemSettings()
  }

  extension NotificationAuthorizationControlling {
    /// Returns settings that hold only the current authorization state.
    func settings() async -> RuntimeNotificationSettings { .authorizationOnly(await state()) }
  }

  /// Reads and requests authorization from the system notification center.
  struct SystemNotificationAuthorizationController: NotificationAuthorizationControlling {
    /// Returns the authorization state; a process without an app bundle is denied.
    func state() async -> RuntimeNotificationAuthorizationState {
      guard let center = bundledNotificationCenter else { return .denied }
      return Self.state(for: await center.notificationSettings().authorizationStatus)
    }

    /// The request result outside an app bundle: denied, with the named text for the missing
    /// notification center.
    static var requestResultWithoutNotificationCenter:
      (RuntimeNotificationAuthorizationState, String?)
    {
      (.denied, RuntimeNotificationDeliveryError.noNotificationCenter.localizedDescription)
    }

    /// Asks macOS for permission to post alerts and sounds and returns the resulting state with the
    /// error text of a failed request.
    func request() async -> (RuntimeNotificationAuthorizationState, String?) {
      guard let center = bundledNotificationCenter else {
        return Self.requestResultWithoutNotificationCenter
      }
      do {
        let authorized = try await center.requestAuthorization(options: [.alert, .sound])
        return (authorized ? .allowed : .denied, nil)
      } catch { return (.denied, error.localizedDescription) }
    }

    /// Returns the authorization state, alert style and sound setting that macOS reports.
    func settings() async -> RuntimeNotificationSettings {
      guard let center = bundledNotificationCenter else { return .authorizationOnly(.denied) }
      let settings = await center.notificationSettings()
      return RuntimeNotificationSettings(
        authorization: Self.state(for: settings.authorizationStatus),
        alertStyle: Self.alertStyle(for: settings.alertStyle),
        soundsEnabled: settings.soundSetting == .enabled
      )
    }

    /// Opens the app's pane in the notification settings of System Settings, or the general
    /// notification settings when that pane does not open.
    @MainActor
    func openSystemSettings() {
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

    /// Returns the authorization state for a system authorization status.
    ///
    /// Provisional and ephemeral authorization count as allowed.
    static func state(for status: UNAuthorizationStatus) -> RuntimeNotificationAuthorizationState {
      switch status {
      case .notDetermined: return .notDetermined
      case .denied: return .denied
      case .authorized, .provisional, .ephemeral: return .allowed
      @unknown default: return .denied
      }
    }

    /// Returns the alert style for a system alert style.
    static func alertStyle(for style: UNAlertStyle) -> RuntimeNotificationAlertStyle {
      switch style {
      case .none: return .none
      case .banner: return .banner
      case .alert: return .alert
      @unknown default: return .unknown
      }
    }
  }

  /// Holds the notification permission that the Notifications pane shows and requests.
  @MainActor
  final class NotificationPermissionModel: ObservableObject {
    /// The authorization state.
    @Published
    private(set) var state: RuntimeNotificationAuthorizationState = .checking
    /// The authorization state with the alert style and the sound setting.
    @Published
    private(set) var settings = RuntimeNotificationSettings.authorizationOnly(.checking)
    /// The error text of the last failed request, or nil.
    @Published
    private(set) var errorMessage: String?

    /// Reads and requests the authorization.
    let authorization: any NotificationAuthorizationControlling
    /// Counts authorization reads so a refresh that finishes after a newer read is dropped.
    private var reads = 0

    /// Creates the model on `authorization`, which defaults to the system notification center.
    init(
      authorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController()
    ) { self.authorization = authorization }

    /// Reads the authorization in the background and publishes it unless a newer read started.
    func refresh() {
      reads += 1
      let read = reads
      Task { [weak self, authorization] in
        let settings = await authorization.settings()
        guard let self, read == self.reads else { return }
        self.settings = settings
        self.state = settings.authorization
      }
    }

    /// Opens System Settings when notifications are denied, or allowed without alerts or sounds;
    /// otherwise asks macOS for permission and then reads the state again.
    func requestOrOpenSettings() {
      if state == .denied
        || (state == .allowed && (settings.alertStyle == .none || settings.soundsEnabled == false))
      {
        authorization.openSystemSettings()
        return
      }
      reads += 1
      Task { [weak self, authorization] in
        let (state, errorMessage) = await authorization.request()
        self?.state = state
        self?.errorMessage = errorMessage
        self?.refresh()
      }
    }
  }

  /// The name and input health of one connected controller.
  struct RuntimeControllerHealthSnapshot: Equatable {
    /// The controller's display name.
    let name: String
    /// The controller's input health.
    let state: ControllerInputHealthState
  }

  /// The controllers, active profiles and input health that the notification monitor compares.
  ///
  /// A group is nil while the service state it comes from has not been read.
  struct RuntimeNotificationSnapshot: Equatable {
    /// The display names of the connected controllers by session token.
    let controllers: [String: String]?
    /// The names of the active profiles by controller model, as `vendorID:productID`.
    let activeProfiles: [String: String]?
    /// The input health of the connected controllers by session token.
    let controllerHealth: [String: RuntimeControllerHealthSnapshot]?

    /// Creates the snapshot from the service state in `viewModel`.
    ///
    /// Several active profiles may share a model (one per app scope); the snapshot uses the one
    /// routing picks without a frontmost app.
    @MainActor
    init(viewModel: RuntimeViewModel) {
      switch viewModel.statusState {
      case .available(let status):
        controllers = Dictionary(
          uniqueKeysWithValues: status.devices.map { ($0.sessionToken.rawValue, $0.name) }
        )
        controllerHealth = Dictionary(
          uniqueKeysWithValues: status.devices.map {
            (
              $0.sessionToken.rawValue,
              RuntimeControllerHealthSnapshot(name: $0.name, state: $0.inputHealth.state)
            )
          }
        )
      case .loading, .unavailable, .error:
        controllers = nil
        controllerHealth = nil
      }

      switch viewModel.remappingState {
      case .available(let snapshot):
        // Several active profiles may share a model (one per app scope); use the one routing
        // picks without a frontmost app.
        var names: [String: String] = [:]
        for active in snapshot.activeProfiles {
          let key = "\(active.vendorID):\(active.productID)"
          guard names[key] == nil,
            let winner = snapshot.activeProfiles.routingActiveProfile(
              vendorID: active.vendorID,
              productID: active.productID
            )
          else { continue }
          names[key] = winner.profileName
        }
        activeProfiles = names
      case .loading, .unavailable, .error: activeProfiles = nil
      }
    }

    /// Creates a snapshot from its three groups.
    init(
      controllers: [String: String]?,
      activeProfiles: [String: String]?,
      controllerHealth: [String: RuntimeControllerHealthSnapshot]? = nil
    ) {
      self.controllers = controllers
      self.activeProfiles = activeProfiles
      self.controllerHealth = controllerHealth
    }
  }

  /// A change between two snapshots that can become a notification.
  enum RuntimeNotificationEvent: Equatable {
    /// A controller connected; the value is its name.
    case controllerConnected(String)
    /// A controller disconnected; the value is its name.
    case controllerDisconnected(String)
    /// The active profile of a controller model changed; the values are the old and new names, and
    /// `to` is nil when the profile was deactivated.
    case activeProfileChanged(from: String?, to: String?)
    /// A controller that was healthy needs attention; the value is its name.
    case controllerNeedsAttention(String)
  }

  /// Finds what changed between two snapshots.
  enum RuntimeNotificationDiff {
    /// Returns the events from `previous` to `current`, in the order connected, disconnected,
    /// profile changes and attention.
    ///
    /// A group that is nil in either snapshot yields no events.
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
      if let previousHealth = previous.controllerHealth,
        let currentHealth = current.controllerHealth
      {
        for identifier in currentHealth.keys.sorted() {
          guard let currentController = currentHealth[identifier],
            currentController.state != .healthy, previousHealth[identifier]?.state == .healthy
          else { continue }
          events.append(.controllerNeedsAttention(currentController.name))
        }
      }
      return events
    }
  }

  /// Posts a notification.
  protocol RuntimeNotificationDelivering {
    /// Posts a notification and prints a failure; nothing waits for the system's answer.
    func deliver(title: String, body: String, sound: Bool)
    /// Posts a notification and returns when the system has accepted it. Throws the system's error,
    /// or `RuntimeNotificationDeliveryError.noNotificationCenter` outside an app bundle.
    nonisolated(nonsending) func deliverAwaitingSystem(
      title: String,
      body: String,
      sound: Bool
    ) async throws
  }

  /// Why a notification could not be posted before the system was asked.
  enum RuntimeNotificationDeliveryError: Error, LocalizedError, Equatable {
    /// The process has no app bundle, so there is no notification center to post to.
    case noNotificationCenter

    /// The localized text of the error.
    var errorDescription: String? {
      switch self {
      case .noNotificationCenter:
        OJDLocalized.string("ui.settings.notifications.noNotificationCenter")
      }
    }
  }

  /// Posts notifications through the system notification center.
  struct SystemRuntimeNotificationDelivery: RuntimeNotificationDelivering {
    /// Posts a notification and prints a failure; nothing waits for the system's answer.
    func deliver(title: String, body: String, sound: Bool) {
      bundledNotificationCenter?.add(Self.request(title: title, body: body, sound: sound)) {
        error in
        if let error { print("[Notifications] Delivery failed: \(error.localizedDescription)") }
      }
    }

    /// Posts a notification and returns when the system has accepted it.
    nonisolated(nonsending) func deliverAwaitingSystem(
      title: String,
      body: String,
      sound: Bool
    ) async throws {
      guard let center = bundledNotificationCenter else {
        throw RuntimeNotificationDeliveryError.noNotificationCenter
      }
      try await center.add(Self.request(title: title, body: body, sound: sound))
    }

    /// Returns the notification request for `title` and `body`, with the default sound when `sound`
    /// is true.
    private static func request(title: String, body: String, sound: Bool) -> UNNotificationRequest {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = sound ? .default : nil
      content.threadIdentifier = "OpenJoystickDriver.runtime"
      return UNNotificationRequest(
        identifier: "OpenJoystickDriver.\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
    }
  }

  /// Shows the app's notifications as banners with sound while the app is in front.
  final class RuntimeNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// The presentation options of a notification while the app is in front.
    static var foregroundPresentationOptions: UNNotificationPresentationOptions {
      [.banner, .sound]
    }

    /// Presents the notification with ``foregroundPresentationOptions``.
    func userNotificationCenter(
      _ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler(Self.foregroundPresentationOptions) }
  }

  /// Compares service snapshots and delivers a notification for each change that the user enabled.
  @MainActor
  final class RuntimeNotificationMonitor {
    /// The settings store that holds the notification preferences.
    let settings: SettingsStore
    /// Posts the notifications.
    let delivery: any RuntimeNotificationDelivering
    /// The snapshot of the last observation, or nil before the first one.
    var previousSnapshot: RuntimeNotificationSnapshot?

    /// Creates the monitor with a settings store and a delivery.
    init(
      settings: SettingsStore = SettingsStore(),
      delivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      self.settings = settings
      self.delivery = delivery
    }
  }

#endif
