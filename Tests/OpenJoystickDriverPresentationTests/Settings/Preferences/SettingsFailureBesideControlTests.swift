import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// A failure of the login item, the pause shortcut, or Send Test Notification shows beside its
/// control; only an unreadable settings file keeps the section.
@Suite
struct SettingsFailureBesideControlTests {
  @MainActor
  private func makeModel(
    launch: LaunchAtLoginStub = LaunchAtLoginStub(isEnabled: false),
    outcome: TestNotificationOutcome = .shown,
    settings: SettingsStore = SettingsStore(directory: RootedDataDirectory.temporary())
  ) -> SettingsPreferencesModel {
    SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(outcome: outcome),
      settings: settings,
      launchAtLogin: launch,
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )
  }

  @Test
  @MainActor
  func loginItemWaitingForApprovalShowsBesideSwitch() {
    let model = makeModel(launch: LaunchAtLoginStub(isEnabled: false, acceptsChanges: false))

    model.setStartAtLogin(true)

    #expect(
      model.failure(beside: .loginItem)
        == OJDLocalized.string("platform.macos.ui.settings.general.startAtLoginApprovalRequired")
    )
    #expect(model.errorMessage == nil)
    #expect(model.failure(beside: .pauseShortcut) == nil)
  }

  @Test
  @MainActor
  func loginItemSucceedsClearsItsFailure() {
    let launch = LaunchAtLoginStub(isEnabled: false, acceptsChanges: false)
    let model = makeModel(launch: launch)
    model.setStartAtLogin(true)

    model.setStartAtLogin(false)

    #expect(model.failure(beside: .loginItem) == nil)
  }

  @Test
  @MainActor
  func refusedPauseShortcutShowsBesideShortcutRow() {
    let model = makeModel()

    model.pauseShortcutRefused()

    #expect(
      model.failure(beside: .pauseShortcut)
        == OJDLocalized.string("ui.settings.general.pauseShortcutTaken")
    )
    #expect(model.errorMessage == nil)
    #expect(model.failure(beside: .loginItem) == nil)
  }

  @Test
  @MainActor
  func invalidRecordedPauseShortcutShowsBesideShortcutRow() {
    let model = makeModel()

    model.recordPauseShortcut(code: 0x23, modifiers: [.shift])
    #expect(
      model.failure(beside: .pauseShortcut)
        == OJDLocalized.string("ui.settings.general.pauseShortcutInvalid")
    )

    model.recordPauseShortcut(code: 0xFF, modifiers: [.command])
    #expect(model.pauseShortcut == nil)
    #expect(model.failure(beside: .pauseShortcut) != nil)

    model.recordPauseShortcut(code: 0x23, modifiers: [.command])
    #expect(model.pauseShortcut?.text == "Command+P")
    #expect(model.failure(beside: .pauseShortcut) == nil)
  }

  @Test
  @MainActor
  func storedPauseShortcutClearsItsFailure() {
    let model = makeModel()
    model.pauseShortcutRefused()

    model.setPauseShortcut(nil)

    #expect(model.failure(beside: .pauseShortcut) == nil)
  }

  @Test
  @MainActor
  func failedTestNotificationShowsBesideButton() async {
    let model = makeModel(outcome: .noAnswer)

    model.sendTestNotification()
    await waitUntil("the test failure") { model.failure(beside: .testNotification) != nil }

    #expect(model.failure(beside: .testNotification) == OJDLocalized.string("error.E2036.message"))
    #expect(model.errorMessage == nil)
  }

  @Test
  @MainActor
  func lostTestReportShowsBesideButton() async {
    let model = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(reportAccepted: false),
      settings: SettingsStore(directory: RootedDataDirectory.temporary()),
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )

    model.answerTestNotification(UUID())
    await waitUntil("the lost report") { model.failure(beside: .testNotification) != nil }

    #expect(
      model.failure(beside: .testNotification)
        == OJDLocalized.string("ui.settings.notifications.testReportLost")
    )
    #expect(model.errorMessage == nil)
  }

  @Test
  @MainActor
  func shownTestNotificationClearsItsFailure() async {
    let requester = TestNotificationRequestStub(outcome: .noAnswer)
    let model = SettingsPreferencesModel(
      testNotifications: requester,
      settings: SettingsStore(directory: RootedDataDirectory.temporary()),
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .allowed)
    )
    model.sendTestNotification()
    await waitUntil("the failure") { model.failure(beside: .testNotification) != nil }

    requester.setOutcome(.shown)
    model.sendTestNotification()
    await waitUntil("cleared") { model.failure(beside: .testNotification) == nil }

    #expect(model.failure(beside: .testNotification) == nil)
  }

  @Test
  @MainActor
  func unreadableSettingsFileKeepsItsSectionEvenWhenControlStartedWrite() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = makeModel(settings: settings)
    try FileManager.default.createDirectory(
      at: settings.folderURL,
      withIntermediateDirectories: true
    )
    try Data("not a property list".utf8).write(to: settings.userFileURL)

    model.setPauseShortcut(nil)

    #expect(model.settingsFileError != nil)
    #expect(model.errorMessage != nil)
    #expect(model.failure(beside: .pauseShortcut) == nil)
  }
}
