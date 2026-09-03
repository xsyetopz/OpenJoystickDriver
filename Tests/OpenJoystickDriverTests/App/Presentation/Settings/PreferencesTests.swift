import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite struct PreferencesTests {
  @Test @MainActor func startAtLoginReflectsTheNativeControllerResult() {
    let launch = LaunchAtLoginStub(isEnabled: false)
    let model = SettingsPreferencesModel(
      defaults: .standard,
      launchAtLogin: launch,
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setStartAtLogin(true)

    #expect(model.startAtLogin)
    #expect(launch.setValues == [true])
  }

  @Test @MainActor func enablingNotificationsRequestsNativeAuthorization() async throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let authorization = NotificationAuthorizationStub(state: .notDetermined)
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization
    )

    model.setControllerNotifications(true)
    await waitUntil { model.controllerNotifications }

    #expect(authorization.requestCount == 1)
    #expect(defaults.bool(forKey: ApplicationPreferenceKeys.controllerNotifications))
    #expect(model.notificationAuthorization == .allowed)
  }

  @Test @MainActor func disablingNotificationsPersistsImmediately() throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: ApplicationPreferenceKeys.controllerNotifications)
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setControllerNotifications(false)

    #expect(!model.controllerNotifications)
    #expect(!defaults.bool(forKey: ApplicationPreferenceKeys.controllerNotifications))
  }

  @Test @MainActor func notificationEventsAndSoundPersistIndependently() async throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )

    model.setControllerDisconnectedNotifications(true)
    model.setProfileDeactivatedNotifications(true)
    model.setNotificationSounds(false)
    await waitUntil {
      model.controllerDisconnectedNotifications && model.profileDeactivatedNotifications
    }

    #expect(defaults.bool(forKey: ApplicationPreferenceKeys.controllerDisconnectedNotifications))
    #expect(defaults.bool(forKey: ApplicationPreferenceKeys.profileDeactivatedNotifications))
    #expect(!defaults.bool(forKey: ApplicationPreferenceKeys.notificationSounds))
  }

  @Test @MainActor func testNotificationUsesNativeAuthorizationAndSoundPreference() async throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(false, forKey: ApplicationPreferenceKeys.notificationSounds)
    let authorization = NotificationAuthorizationStub(state: .notDetermined)
    let delivery = PreferencesNotificationDeliverySpy()
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization,
      notificationDelivery: delivery
    )

    model.sendTestNotification()
    await waitUntil { delivery.deliveryCount == 1 }

    #expect(authorization.requestCount == 1)
    #expect(delivery.deliveryCount == 1)
    #expect(delivery.lastSound == false)
  }

  @Test @MainActor func refreshPublishesAuthorizationGrantedOutsideTheApp() async {
    let authorization = NotificationAuthorizationStub(state: .denied)
    let model = SettingsPreferencesModel(
      defaults: .standard,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: authorization
    )
    authorization.currentState = .allowed

    model.refreshNotificationAuthorization()
    await waitUntil { model.notificationAuthorization == .allowed }

    #expect(model.notificationAuthorization == .allowed)
  }

  @Test @MainActor func startAtLoginReportsWhenNativeApprovalIsStillRequired() {
    let launch = LaunchAtLoginStub(isEnabled: false, acceptsChanges: false)
    let model = SettingsPreferencesModel(
      defaults: .standard,
      launchAtLogin: launch,
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setStartAtLogin(true)

    #expect(!model.startAtLogin)
    #expect(model.errorMessage != nil)
  }

  @Test @MainActor func prereleaseChoiceAndUpdateCheckShareTheCLIUpdateEngine() async throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let checker = UpdateCheckerStub(result: .upToDate("v1.2.3"))
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied),
      updateChecker: checker
    )

    model.setIncludePrereleaseUpdates(true)
    model.checkForUpdates()
    await waitUntil { model.updateState == .upToDate("v1.2.3") }

    #expect(defaults.bool(forKey: ApplicationPreferenceKeys.includePrereleaseUpdates))
    #expect(await checker.includePrereleaseArguments == [true])
  }

  @Test @MainActor func developerToolsChoicePersists() throws {
    let suiteName = "PreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = SettingsPreferencesModel(
      defaults: defaults,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )

    model.setDeveloperToolsEnabled(true)

    #expect(model.developerToolsEnabled)
    #expect(defaults.bool(forKey: ApplicationPreferenceKeys.developerTools))
  }

  @MainActor private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() { await Task.yield() }
  }
}

private final class LaunchAtLoginStub: LaunchAtLoginControlling {
  let isAvailable = true
  var isEnabled: Bool
  private(set) var setValues: [Bool] = []
  private let acceptsChanges: Bool

  init(isEnabled: Bool, acceptsChanges: Bool = true) {
    self.isEnabled = isEnabled
    self.acceptsChanges = acceptsChanges
  }

  func setEnabled(_ enabled: Bool) {
    setValues.append(enabled)
    if acceptsChanges { isEnabled = enabled }
  }
}

private final class NotificationAuthorizationStub: NotificationAuthorizationControlling,
  @unchecked Sendable
{
  var currentState: RuntimeNotificationAuthorizationState
  private(set) var requestCount = 0

  init(state: RuntimeNotificationAuthorizationState) { currentState = state }

  func state(completion: @escaping @Sendable (RuntimeNotificationAuthorizationState) -> Void) {
    completion(currentState)
  }

  func request(
    completion: @escaping @Sendable (RuntimeNotificationAuthorizationState, String?) -> Void
  ) {
    requestCount += 1
    currentState = .allowed
    completion(.allowed, nil)
  }

  @MainActor func openSystemSettings() {}
}

private actor UpdateCheckerStub: ApplicationUpdateChecking {
  let result: UpdateCheckState
  private(set) var includePrereleaseArguments: [Bool] = []

  init(result: UpdateCheckState) { self.result = result }

  func check(currentVersion: String, includePrereleases: Bool) async -> UpdateCheckState {
    await Task.yield()
    includePrereleaseArguments.append(includePrereleases)
    return result
  }
}

private final class PreferencesNotificationDeliverySpy: RuntimeNotificationDelivering {
  private(set) var deliveryCount = 0
  private(set) var lastSound: Bool?

  func deliver(title: String, body: String, sound: Bool) {
    deliveryCount += 1
    lastSound = sound
  }
}
