#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// Checks for a newer release of the app.
  protocol ApplicationUpdateChecking: Sendable {
    /// Returns the result of checking the latest release against `currentVersion`, with prereleases
    /// included when `includePrereleases` is true.
    func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState
  }

  extension UpdateChecker: ApplicationUpdateChecking {}

  /// The app's side of the test notification: the request to the service and the report back.
  protocol TestNotificationRequesting: Sendable {
    /// Asks the service to announce a test notification and returns how it ended.
    func requestTestNotification() async throws -> TestNotificationOutcome
    /// Answers an announcement this app took from the service.
    func reportTestNotification(
      _ announcement: UUID,
      outcome: TestNotificationOutcome
    )
      async throws -> Bool
  }

  extension ApplicationServiceClientGateway: TestNotificationRequesting {}

  /// The switches of the Settings window, stored in the user settings file, and the update check
  /// and notification permission state that the panes show.
  @MainActor
  final class SettingsPreferencesModel: ObservableObject {
    /// Whether the app starts at login.
    @Published
    private(set) var startAtLogin: Bool
    /// Whether a notification posts when a controller connects.
    @Published
    private(set) var controllerNotifications: Bool
    /// Whether a notification posts when a controller disconnects.
    @Published
    private(set) var controllerDisconnectedNotifications: Bool
    /// Whether a notification posts when a profile activates.
    @Published
    private(set) var profileNotifications: Bool
    /// Whether a notification posts when a profile deactivates.
    @Published
    private(set) var profileDeactivatedNotifications: Bool
    /// Whether notifications play a sound.
    @Published
    private(set) var notificationSounds: Bool
    /// Whether macOS lets the app post notifications.
    @Published
    private(set) var notificationAuthorization: RuntimeNotificationAuthorizationState
    /// What macOS allows the app to do with notifications.
    @Published
    private(set) var notificationSystemSettings: RuntimeNotificationSettings
    /// Whether the menu bar item shows.
    @Published
    private(set) var showInMenuBar: Bool
    /// Whether the Dock icon shows.
    @Published
    private(set) var showInDock: Bool
    /// Whether the app checks for updates automatically.
    @Published
    private(set) var checkUpdatesAutomatically: Bool
    /// Whether update checks include prereleases.
    @Published
    private(set) var includePrereleaseUpdates: Bool
    /// Whether Settings > Advanced shows the developer tools.
    @Published
    private(set) var developerToolsEnabled: Bool
    /// The result of the last update check, or idle before a check runs.
    @Published
    private(set) var updateState: UpdateCheckState = .idle
    /// The text of the error that the panes show, or nil for none.
    @Published
    private(set) var errorMessage: String?
    /// Why the settings file cannot be used, or `nil` while it can.
    ///
    /// While it is set, the switches show the built-in defaults and features that read settings do
    /// nothing.
    @Published
    private(set) var settingsFileError: SettingsStoreError?

    /// Whether the login item is available on this macOS version.
    let launchAtLoginIsAvailable: Bool

    /// Called when a read finds the settings file usable again after an error, so that the work
    /// skipped while the file could not be read can run.
    var settingsRecovered: (@MainActor () -> Void)?

    /// The user settings store.
    private let settings: SettingsStore
    /// Reloads the settings when the settings file changes.
    private var watcher: SettingsWatcher?
    /// The login item.
    private let launchAtLogin: any LaunchAtLoginControlling
    /// Reads and requests the notification permission.
    private let notificationAuthorizationController: any NotificationAuthorizationControlling
    /// Counts authorization reads.
    ///
    /// The controller answers off the main actor, so a refresh that started before a newer read can
    /// finish after it; its result is then stale and dropped.
    private var notificationAuthorizationReads = 0
    /// Checks for updates.
    private let updateChecker: any ApplicationUpdateChecking
    /// Posts the update available notification and the test notification.
    private let notificationDelivery: any RuntimeNotificationDelivering

    /// Asks the service to announce the test notification and reports how it ended.
    private let testNotifications: any TestNotificationRequesting

    /// Creates the model, reads the settings and the notification permission, and watches the
    /// settings file for changes.
    init(
      testNotifications: any TestNotificationRequesting,
      settings: SettingsStore = SettingsStore(),
      launchAtLogin: (any LaunchAtLoginControlling)? = nil,
      notificationAuthorization: any NotificationAuthorizationControlling =
        SystemNotificationAuthorizationController(),
      updateChecker: any ApplicationUpdateChecking = UpdateChecker(),
      notificationDelivery: any RuntimeNotificationDelivering = SystemRuntimeNotificationDelivery()
    ) {
      let launchAtLogin = launchAtLogin ?? SystemLaunchAtLoginController(settings: settings)
      self.testNotifications = testNotifications
      self.settings = settings
      self.launchAtLogin = launchAtLogin
      self.notificationAuthorizationController = notificationAuthorization
      self.updateChecker = updateChecker
      self.notificationDelivery = notificationDelivery
      self.launchAtLoginIsAvailable = launchAtLogin.isAvailable
      self.startAtLogin = launchAtLogin.isEnabled
      self.notificationAuthorization = .checking
      self.notificationSystemSettings = .authorizationOnly(.checking)
      self.controllerNotifications = ApplicationSettingKey.notifyControllerConnected.defaultValue
      self.controllerDisconnectedNotifications =
        ApplicationSettingKey.notifyControllerDisconnected.defaultValue
      self.profileNotifications = ApplicationSettingKey.notifyProfileActivated.defaultValue
      self.profileDeactivatedNotifications =
        ApplicationSettingKey.notifyProfileDeactivated.defaultValue
      self.notificationSounds = ApplicationSettingKey.notifySounds.defaultValue
      self.showInMenuBar = ApplicationSettingKey.showInMenuBar.defaultValue
      self.showInDock = ApplicationSettingKey.showInDock.defaultValue
      self.checkUpdatesAutomatically = ApplicationSettingKey.updatesCheckAutomatically.defaultValue
      self.includePrereleaseUpdates = ApplicationSettingKey.updatesIncludePrereleases.defaultValue
      self.developerToolsEnabled = ApplicationSettingKey.developerTools.defaultValue
      reloadSettings()
      // A change from `ojd setting` or another process shows while the window is open.
      watcher = SettingsWatcher(store: settings) { [weak self] in
        Task { @MainActor in self?.reloadSettings() }
      }
      refreshNotificationAuthorization()
    }

    /// Reads the user settings file and the login item again; a file that cannot be used shows in
    /// `errorMessage` and `settingsFileError` and leaves the switches as they are.
    func reloadSettings() {
      startAtLogin = launchAtLogin.isEnabled
      let stored: SettingsDocument
      do { stored = try settings.load() } catch {
        report(error)
        return
      }
      let recovered = settingsFileError != nil
      if recovered {
        settingsFileError = nil
        errorMessage = nil
      }
      func value(_ key: ApplicationSettingKey) -> Bool { stored[key] ?? key.defaultValue }
      controllerNotifications = value(.notifyControllerConnected)
      controllerDisconnectedNotifications = value(.notifyControllerDisconnected)
      profileNotifications = value(.notifyProfileActivated)
      profileDeactivatedNotifications = value(.notifyProfileDeactivated)
      notificationSounds = value(.notifySounds)
      showInMenuBar = value(.showInMenuBar)
      showInDock = value(.showInDock)
      checkUpdatesAutomatically = value(.updatesCheckAutomatically)
      includePrereleaseUpdates = value(.updatesIncludePrereleases)
      developerToolsEnabled = value(.developerTools)
      if recovered { settingsRecovered?() }
    }

    /// Turns the login item on or off.
    ///
    /// A login item that macOS leaves waiting for approval shows a message in ``errorMessage``, and
    /// so does a failure.
    func setStartAtLogin(_ enabled: Bool) {
      do {
        try launchAtLogin.setEnabled(enabled)
        startAtLogin = launchAtLogin.isEnabled
        if enabled && !startAtLogin {
          errorMessage = OJDLocalized.string(
            "platform.macos.ui.settings.general.startAtLoginApprovalRequired"
          )
        } else {
          errorMessage = nil
        }
      } catch {
        startAtLogin = launchAtLogin.isEnabled
        report(error)
      }
    }

    /// Turns the notification for a connecting controller on or off; turning it on needs the macOS
    /// notification permission, which is requested first.
    func setControllerNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllers)
    }

    /// Turns the notification for an activating profile on or off; turning it on needs the macOS
    /// notification permission, which is requested first.
    func setProfileNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profiles)
    }

    /// Turns the notification for a disconnecting controller on or off; turning it on needs the
    /// macOS notification permission, which is requested first.
    func setControllerDisconnectedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .controllerDisconnections)
    }

    /// Turns the notification for a deactivating profile on or off; turning it on needs the macOS
    /// notification permission, which is requested first.
    func setProfileDeactivatedNotifications(_ enabled: Bool) {
      setNotificationPreference(enabled, preference: .profileDeactivations)
    }

    /// Turns notification sounds on or off.
    func setNotificationSounds(_ enabled: Bool) {
      guard persist(.notifySounds, enabled) else { return }
      notificationSounds = enabled
    }

    /// Asks the service to announce a test notification to the app and shows how it ended in
    /// `errorMessage`: nothing for `shown`, the named text for every other outcome.
    ///
    /// The announcement reaches this app's own wait, which calls `answerTestNotification`.
    func sendTestNotification() {
      Task { @MainActor [weak self, testNotifications] in
        do {
          let outcome = try await testNotifications.requestTestNotification()
          self?.errorMessage = Self.message(for: outcome)
        } catch { self?.report(error) }
      }
    }

    /// The text of an outcome that is not `shown`.
    static func message(for outcome: TestNotificationOutcome) -> String? {
      switch outcome {
      case .shown: return nil
      case .denied: return OJDLocalized.string("error.E2037.message")
      case .failed(let reason): return reason
      case .noAnswer: return OJDLocalized.string("error.E2036.message")
      }
    }

    /// Shows the test notification the service announced and reports how it ended.
    ///
    /// A report that fails shows its error in ``errorMessage``; a report that the service does not
    /// wait for, because the `ojd` request ended first, shows
    /// `ui.settings.notifications.testReportLost`.
    func answerTestNotification(_ announcement: UUID) {
      Task { @MainActor [weak self, testNotifications] in
        guard let self else { return }
        let outcome = await self.showTestNotification()
        do {
          let accepted = try await testNotifications.reportTestNotification(
            announcement,
            outcome: outcome
          )
          if !accepted {
            self.errorMessage = OJDLocalized.string("ui.settings.notifications.testReportLost")
          }
        } catch { self.report(error) }
      }
    }

    /// Delivers the test notification, asking the system for permission first when it is not
    /// decided.
    ///
    /// A delivery the system rejects, or one with no notification center, is `failed`.
    func showTestNotification() async -> TestNotificationOutcome {
      notificationAuthorizationReads += 1
      var state = await notificationAuthorizationController.state()
      notificationAuthorization = state
      if state == .notDetermined || state == .checking {
        notificationAuthorizationReads += 1
        let (requested, errorDescription) = await notificationAuthorizationController.request()
        state = requested
        notificationAuthorization = requested
        if let errorDescription { return .failed(errorDescription) }
      }
      guard state == .allowed else { return .denied }
      do {
        try await notificationDelivery.deliverAwaitingSystem(
          title: OJDLocalized.string("notify.testTitle"),
          body: OJDLocalized.string("notify.testBody"),
          sound: notificationSounds
        )
      } catch { return .failed(error.localizedDescription) }
      refreshNotificationAuthorization()
      return .shown
    }

    /// Shows or hides the menu bar item.
    func setShowInMenuBar(_ enabled: Bool) {
      guard persist(.showInMenuBar, enabled) else { return }
      showInMenuBar = enabled
    }

    /// Stores that the user removed the menu bar item: Show in menu bar off and Show in Dock on,
    /// in one write so that the two are never both off.
    ///
    /// Returns whether the write succeeded; a failure shows in ``errorMessage`` and leaves both
    /// switches as they were.
    func menuBarItemWasRemoved() -> Bool {
      guard persist([.showInMenuBar: false, .showInDock: true]) else { return false }
      showInMenuBar = false
      showInDock = true
      return true
    }

    /// Shows or hides the Dock icon.
    func setShowInDock(_ enabled: Bool) {
      guard persist(.showInDock, enabled) else { return }
      showInDock = enabled
    }

    /// Whether Show in Menu Bar cannot be turned off, because the Dock icon is off.
    ///
    /// The two cannot both be off.
    var showInMenuBarIsLocked: Bool { showInMenuBar && !showInDock }

    /// Whether Show in Dock cannot be turned off, because the menu bar item is off.
    ///
    /// The two cannot both be off.
    var showInDockIsLocked: Bool { showInDock && !showInMenuBar }

    /// Why Start at login cannot change, or nil while it can.
    var startAtLoginUnavailableReason: String? {
      launchAtLoginIsAvailable
        ? nil : OJDLocalized.string("platform.macos.ui.settings.general.startAtLoginUnavailable")
    }

    /// Turns automatic update checks on or off; turning them on checks at once, so the choice
    /// applies without a restart.
    func setCheckUpdatesAutomatically(_ enabled: Bool) {
      guard persist(.updatesCheckAutomatically, enabled) else { return }
      checkUpdatesAutomatically = enabled
      if enabled { checkForUpdates(announcingAvailableUpdate: true) }
    }

    /// Turns the inclusion of prereleases in update checks on or off.
    func setIncludePrereleaseUpdates(_ enabled: Bool) {
      guard persist(.updatesIncludePrereleases, enabled) else { return }
      includePrereleaseUpdates = enabled
    }

    /// Turns the developer tools of Settings > Advanced on or off.
    func setDeveloperToolsEnabled(_ enabled: Bool) {
      guard persist(.developerTools, enabled) else { return }
      developerToolsEnabled = enabled
    }

    /// Checks for a newer version and shows the result in `updateState`.
    ///
    /// With `announcingAvailableUpdate`, a newer version also posts a notification; an up-to-date
    /// result or a failure posts none and stays in `updateState`.
    func checkForUpdates(announcingAvailableUpdate: Bool = false) {
      guard updateState != .checking else { return }
      updateState = .checking
      let includePrereleases = includePrereleaseUpdates
      Task { @MainActor [weak self, updateChecker] in
        let state = await updateChecker.check(
          currentVersion: ApplicationVersion.current,
          includePrereleases: includePrereleases
        )
        guard let self else { return }
        self.updateState = state
        if announcingAvailableUpdate, case .available(let info) = state {
          self.notificationDelivery.deliver(
            title: OJDLocalized.string("ui.settings.general.updateAvailable"),
            body: OJDLocalized.formatted("ui.settings.general.updateAvailableBody", info.tagName),
            sound: self.notificationSounds
          )
        }
      }
    }

    /// Opens the page of the available release in the default browser; does nothing unless a
    /// release is available.
    func openAvailableUpdate() {
      guard case .available(let info) = updateState else { return }
      NSWorkspace.shared.open(info.htmlURL)
    }

    /// Opens the notification settings of the app in System Settings.
    func openNotificationSettings() { notificationAuthorizationController.openSystemSettings() }

    /// Hides the error.
    ///
    /// An error about the settings file stays while the file cannot be used, because the buttons
    /// that fix it are part of it.
    func dismissError() {
      guard settingsFileError == nil else { return }
      errorMessage = nil
    }

    /// Reads the notification permission.
    ///
    /// While macOS denies it, the four event notifications are turned off.
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
          let notifications: [ApplicationSettingKey] = [
            .notifyControllerConnected, .notifyControllerDisconnected, .notifyProfileActivated,
            .notifyProfileDeactivated,
          ]
          guard self.persist(Dictionary(uniqueKeysWithValues: notifications.map { ($0, false) }))
          else { return }
          self.controllerNotifications = false
          self.controllerDisconnectedNotifications = false
          self.profileNotifications = false
          self.profileDeactivatedNotifications = false
        }
      }
    }

    /// Stores one setting in the user settings file and returns whether it succeeded; a failure
    /// shows in ``errorMessage``.
    private func persist(_ key: ApplicationSettingKey, _ value: Bool) -> Bool {
      persist([key: value])
    }

    /// Stores `values` in the user settings file and returns whether it succeeded; a failure shows
    /// in ``errorMessage``.
    private func persist(_ values: [ApplicationSettingKey: Bool]) -> Bool {
      do {
        try settings.update(values)
        return true
      } catch {
        report(error)
        return false
      }
    }

    /// Shows `error`; a settings file error that makes the file unusable is also kept typed.
    private func report(_ error: any Error) {
      errorMessage = error.localizedDescription
      if let error = error as? SettingsStoreError, error.fileIsUnusable {
        settingsFileError = error
      }
    }

    /// Moves the settings file to the Trash and reads the defaults; a failure shows in
    /// `errorMessage`.
    func resetSettings() {
      do { try settings.moveToTrash() } catch {
        errorMessage = error.localizedDescription
        return
      }
      reloadSettings()
    }

    /// Shows the settings file in Finder, or its folder while there is no file.
    func showSettingsFileInFinder() {
      let file = settings.userFileURL
      if FileManager.default.fileExists(atPath: file.path) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
      } else {
        NSWorkspace.shared.open(settings.folderURL)
      }
    }

    /// Turns a notification preference on or off; turning it on reads the macOS notification
    /// permission and requests it when it is undecided.
    private func setNotificationPreference(_ enabled: Bool, preference: NotificationPreference) {
      guard enabled else {
        guard persist(preference, false) else { return }
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
          self.acceptNotificationPreference(preference)
          self.refreshNotificationAuthorization()
        case .notDetermined, .checking: self.requestNotificationAuthorization(preference)
        case .denied: self.rejectNotificationPreference(preference, errorDescription: nil)
        }
      }
    }

    /// Asks macOS for the notification permission, then keeps `preference` on or turns it off.
    private func requestNotificationAuthorization(_ preference: NotificationPreference) {
      notificationAuthorizationReads += 1
      Task { [weak self, notificationAuthorizationController] in
        let (state, errorDescription) = await notificationAuthorizationController.request()
        guard let self else { return }
        self.notificationAuthorization = state
        if state == .allowed && errorDescription == nil {
          self.acceptNotificationPreference(preference)
        } else {
          self.rejectNotificationPreference(preference, errorDescription: errorDescription)
        }
      }
    }

    /// Stores `preference` as on and clears the error.
    private func acceptNotificationPreference(_ preference: NotificationPreference) {
      guard persist(preference, true) else { return }
      update(preference, enabled: true)
      errorMessage = nil
    }

    /// Stores `preference` as off and shows `errorDescription`, or the text for denied
    /// notifications when it is nil.
    private func rejectNotificationPreference(
      _ preference: NotificationPreference,
      errorDescription: String?
    ) {
      if persist(preference, false) {
        update(preference, enabled: false)
      }
      errorMessage =
        errorDescription
        ?? OJDLocalized.string(
          "platform.macos.ui.settings.notifications.notificationsDenied"
        )
    }

    /// Sets the switch of `preference`.
    private func update(_ preference: NotificationPreference, enabled: Bool) {
      switch preference {
      case .controllers: controllerNotifications = enabled
      case .controllerDisconnections: controllerDisconnectedNotifications = enabled
      case .profiles: profileNotifications = enabled
      case .profileDeactivations: profileDeactivatedNotifications = enabled
      }
    }

    /// Stores the setting of `preference` and returns whether it succeeded.
    private func persist(_ preference: NotificationPreference, _ value: Bool) -> Bool {
      persist(preference.settingKey, value)
    }
  }

  /// The notification switch of one event.
  private enum NotificationPreference: Sendable, Equatable {
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

#endif
