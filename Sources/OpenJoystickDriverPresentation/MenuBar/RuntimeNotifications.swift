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
    func state() async -> RuntimeNotificationAuthorizationState
    /// Requests authorization and returns the resulting state with an optional error description.
    func request() async -> (RuntimeNotificationAuthorizationState, String?)
    func settings() async -> RuntimeNotificationSettings
    @MainActor
    func openSystemSettings()
  }

  extension NotificationAuthorizationControlling {
    func settings() async -> RuntimeNotificationSettings { .authorizationOnly(await state()) }
  }

  struct SystemNotificationAuthorizationController: NotificationAuthorizationControlling {
    func state() async -> RuntimeNotificationAuthorizationState {
      guard let center = bundledNotificationCenter else { return .denied }
      return Self.state(for: await center.notificationSettings().authorizationStatus)
    }

    func request() async -> (RuntimeNotificationAuthorizationState, String?) {
      guard let center = bundledNotificationCenter else {
        return (.denied, "Notifications require the OpenJoystickDriver app bundle.")
      }
      do {
        let authorized = try await center.requestAuthorization(options: [.alert, .sound])
        return (authorized ? .allowed : .denied, nil)
      } catch { return (.denied, error.localizedDescription) }
    }

    func settings() async -> RuntimeNotificationSettings {
      guard let center = bundledNotificationCenter else { return .authorizationOnly(.denied) }
      let settings = await center.notificationSettings()
      return RuntimeNotificationSettings(
        authorization: Self.state(for: settings.authorizationStatus),
        alertStyle: Self.alertStyle(for: settings.alertStyle),
        soundsEnabled: settings.soundSetting == .enabled
      )
    }

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

    static func state(for status: UNAuthorizationStatus) -> RuntimeNotificationAuthorizationState {
      switch status {
      case .notDetermined: return .notDetermined
      case .denied: return .denied
      case .authorized, .provisional, .ephemeral: return .allowed
      @unknown default: return .denied
      }
    }

    static func alertStyle(for style: UNAlertStyle) -> RuntimeNotificationAlertStyle {
      switch style {
      case .none: return .none
      case .banner: return .banner
      case .alert: return .alert
      @unknown default: return .unknown
      }
    }
  }

  @MainActor
  final class NotificationPermissionModel: ObservableObject {
    @Published
    private(set) var state: RuntimeNotificationAuthorizationState = .checking
    @Published
    private(set) var settings = RuntimeNotificationSettings.authorizationOnly(.checking)
    @Published
    private(set) var errorMessage: String?

    let authorization: any NotificationAuthorizationControlling
    /// Counts authorization reads so a refresh that finishes after a newer read is dropped.
    private var reads = 0

    init(
      authorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController()
    ) { self.authorization = authorization }

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

  struct RuntimeControllerHealthSnapshot: Equatable {
    let name: String
    let state: ControllerInputHealthState
  }

  struct RuntimeNotificationSnapshot: Equatable {
    let controllers: [String: String]?
    let activeProfiles: [String: String]?
    let controllerHealth: [String: RuntimeControllerHealthSnapshot]?

    @MainActor
    init(viewModel: RuntimeViewModel) {
      switch viewModel.statusState {
      case .available(let status):
        controllers = Dictionary(
          uniqueKeysWithValues: status.devices.map { ($0.runtimeIdentifier, $0.name) }
        )
        controllerHealth = Dictionary(
          uniqueKeysWithValues: status.devices.map {
            (
              $0.runtimeIdentifier,
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

  enum RuntimeNotificationEvent: Equatable {
    case controllerConnected(String)
    case controllerDisconnected(String)
    case activeProfileChanged(from: String?, to: String?)
    case controllerNeedsAttention(String)
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
      bundledNotificationCenter?.add(request) { error in
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

  @MainActor
  final class RuntimeNotificationMonitor {
    let defaults: UserDefaults
    let delivery: any RuntimeNotificationDelivering
    var previousSnapshot: RuntimeNotificationSnapshot?

    init(
      defaults: UserDefaults = .standard,
      delivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      self.defaults = defaults
      self.delivery = delivery
    }
  }

#endif
