import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct SettingsFileRecoveryTests {
  private let root = RootedDataDirectory.temporary()
  private let trash = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ojd-settings-recovery-trash-\(UUID().uuidString)"
  )

  private var store: SettingsStore {
    let trash = trash
    return SettingsStore(directory: root) { url in
      try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
      try FileManager.default.moveItem(
        at: url,
        to: trash.appendingPathComponent(url.lastPathComponent)
      )
    }
  }

  /// A file that turns Show in menu bar off and leaves Show in Dock at its default, off.
  private func writeRejectedFile() throws {
    try FileManager.default.createDirectory(
      at: store.folderURL,
      withIntermediateDirectories: true
    )
    try PropertyListFixture.data(
      json: #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings", "#
        + #""showInMenuBar": false}"#
    ).write(to: store.userFileURL)
  }

  @MainActor
  private func makeModel() -> SettingsPreferencesModel {
    SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: store,
      launchAtLogin: RecoveryLaunchAtLoginStub(),
      notificationAuthorization: RecoveryAuthorizationStub()
    )
  }

  @Test
  @MainActor
  func modelExposesTypedErrorOfRejectedFile() throws {
    try writeRejectedFile()

    let model = makeModel()

    #expect(model.settingsFileError == .storedNoVisibleEntryPoint(file: store.userFileURL.path))
    #expect(model.errorMessage == model.settingsFileError?.localizedDescription)
  }

  @Test
  @MainActor
  func usableFileLeavesNoError() {
    #expect(makeModel().settingsFileError == nil)
  }

  @Test
  @MainActor
  func changeThatFailsOnRejectedFileKeepsTypedError() throws {
    let model = makeModel()
    try writeRejectedFile()

    model.setDeveloperToolsEnabled(true)

    #expect(model.settingsFileError == .storedNoVisibleEntryPoint(file: store.userFileURL.path))
    #expect(!model.developerToolsEnabled)
  }

  @Test
  @MainActor
  func resetMovesFileToTrashAndClearsError() throws {
    try writeRejectedFile()
    let model = makeModel()

    model.resetSettings()

    #expect(model.settingsFileError == nil)
    #expect(model.errorMessage == nil)
    #expect(!FileManager.default.fileExists(atPath: store.userFileURL.path))
    #expect(
      FileManager.default.fileExists(
        atPath: trash.appendingPathComponent(SettingsStore.fileName).path
      )
    )
    #expect(model.showInMenuBar)
  }

  @Test
  @MainActor
  func resetThatFailsShowsWhyAndKeepsError() throws {
    try writeRejectedFile()
    let failing = SettingsStore(directory: root) { _ in throw CocoaError(.fileWriteNoPermission) }
    let model = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: failing,
      launchAtLogin: RecoveryLaunchAtLoginStub(),
      notificationAuthorization: RecoveryAuthorizationStub()
    )

    model.resetSettings()

    #expect(model.settingsFileError == .storedNoVisibleEntryPoint(file: failing.userFileURL.path))
    #expect(
      model.errorMessage
        == SettingsStoreError.cannotReset(file: failing.userFileURL.path).localizedDescription
    )
  }

  @Test
  func startupOffersRecoveryOnlyForUnusableFile() {
    let error = SettingsStoreError.damaged(file: "/tmp/Settings.plist")

    #expect(SettingsFileStartup.decide(settingsError: nil) == .proceed)
    #expect(SettingsFileStartup.decide(settingsError: error) == .offerRecovery(error))
  }

  @Test(arguments: [true, false])
  func menuBarItemShowsWhileSettingsFileCannotBeRead(showInMenuBar: Bool) {
    let error = SettingsStoreError.damaged(file: "/tmp/Settings.plist")

    #expect(
      SettingsFileStartup.statusItemIsShown(showInMenuBar: showInMenuBar, settingsError: error)
    )
    #expect(
      SettingsFileStartup.statusItemIsShown(showInMenuBar: showInMenuBar, settingsError: nil)
        == showInMenuBar
    )
  }

  @Test
  @MainActor
  func alertDefaultsToShowInFinderAndQuitAnswersEscape() {
    let alert = SettingsUnreadableAlert.make(reason: "Reason")

    #expect(alert.messageText == OJDLocalized.string("ui.settings.advanced.unreadableTitle"))
    #expect(alert.informativeText == "Reason")
    #expect(
      alert.buttons.map(\.title) == [
        OJDLocalized.string("platform.macos.ui.settings.advanced.unreadableShowInFinder"),
        OJDLocalized.string("ui.settings.advanced.unreadableResetSettings"),
        MainMenuRenderer.title("ui.menu.app.quit", appName: OJDLocalized.string("term.app.name")),
      ]
    )
    #expect(alert.buttons[0].keyEquivalent == "\r")
    #expect(alert.buttons[1].hasDestructiveAction)
    #expect(alert.buttons[1].keyEquivalent.isEmpty)
    #expect(alert.buttons[2].keyEquivalent == "\u{1b}")
  }

  @Test
  func buttonsMapToTheirChoices() {
    #expect(SettingsUnreadableChoice(response: .alertFirstButtonReturn) == .showInFinder)
    #expect(SettingsUnreadableChoice(response: .alertSecondButtonReturn) == .resetSettings)
    #expect(SettingsUnreadableChoice(response: .alertThirdButtonReturn) == .quit)
  }

  @Test
  @MainActor
  func alertThatOffersMigrationHasMigrateFirstAndMapsItsButtons() {
    let alert = SettingsUnreadableAlert.make(reason: "Reason", offersMigration: true)

    #expect(alert.buttons.map(\.title).first == OJDLocalized.string("ui.migrate.action"))
    #expect(alert.buttons.count == 4)
    let choices = [
      NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn,
      .alertThirdButtonReturn, NSApplication.ModalResponse(rawValue: 1003),
    ].map { SettingsUnreadableChoice(response: $0, offersMigration: true) }
    #expect(choices == [.migrate, .showInFinder, .resetSettings, .quit])
  }

  @Test
  @MainActor
  func launchUpdateCheckSkipsWhileSettingsFileCannotBeRead() {
    let error = SettingsStoreError.damaged(file: "/tmp/Settings.plist")
    var checks = 0

    let outcome = LaunchUpdateCheck(
      settingsError: { error },
      isEnabled: { true },
      check: { checks += 1 }
    ).run()

    #expect(outcome == .skippedSettingsUnreadable(error))
    #expect(checks == 0)
  }

  @Test
  @MainActor
  func launchUpdateCheckReportsWhyItDidOrDidNotRun() {
    var checks = 0

    let enabled = LaunchUpdateCheck(
      settingsError: { nil },
      isEnabled: { true },
      check: { checks += 1 }
    ).run()
    let disabled = LaunchUpdateCheck(
      settingsError: { nil },
      isEnabled: { false },
      check: { checks += 1 }
    ).run()

    #expect(enabled == .checked)
    #expect(disabled == .disabled)
    #expect(checks == 1)
  }

  @Test
  func skipLogNamesFeatureFileAndReason() {
    let error = SettingsStoreError.damaged(file: "/tmp/Settings.plist")

    let message = SettingsSkipLog.message(
      feature: "the launch update check",
      file: "/tmp/Settings.plist",
      error: error
    )

    #expect(message.hasPrefix("[Settings] /tmp/Settings.plist cannot be read, skipping the launch"))
    #expect(message.contains(error.localizedDescription))
  }

  @Test
  @MainActor
  func notificationsAreNotDeliveredWhileSettingsFileCannotBeRead() throws {
    try store.set(.notifyControllerConnected, to: true)
    let delivery = RecoveryDeliverySpy()
    let monitor = RuntimeNotificationMonitor(settings: store, delivery: delivery)
    monitor.observe(RuntimeNotificationSnapshot(controllers: [:], activeProfiles: [:]))
    monitor.observe(RuntimeNotificationSnapshot(controllers: ["a": "Pad"], activeProfiles: [:]))
    // With the choice stored and the file readable, the connection is delivered.
    #expect(delivery.total == 1)

    try store.set(.showInDock, to: true)
    let url = store.userFileURL
    var document = try PropertyListFixture.dictionary(at: url)
    document["showInDock"] = false
    document["showInMenuBar"] = false
    try PropertyListFixture.data(tree: document).write(to: url)
    #expect(throws: SettingsStoreError.self) { try store.load() }
    monitor.observe(RuntimeNotificationSnapshot(controllers: [:], activeProfiles: [:]))
    monitor.observe(RuntimeNotificationSnapshot(controllers: ["b": "Pad 2"], activeProfiles: [:]))

    #expect(delivery.total == 1)
  }

  @Test
  @MainActor
  func errorStaysWithItsButtonsUntilFileIsUsable() throws {
    try writeRejectedFile()
    let model = makeModel()

    model.dismissError()

    #expect(model.errorMessage != nil)
    #expect(model.settingsFileError != nil)
  }

  @Test
  @MainActor
  func resetRunsWorkThatWaitedForFile() throws {
    try writeRejectedFile()
    let model = makeModel()
    var recovered = 0
    model.settingsRecovered = { recovered += 1 }

    model.resetSettings()

    #expect(recovered == 1)
  }

  @Test
  @MainActor
  func failedResetRunsNothing() throws {
    try writeRejectedFile()
    let failing = SettingsStore(directory: root) { _ in throw CocoaError(.fileWriteNoPermission) }
    let model = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: failing,
      launchAtLogin: RecoveryLaunchAtLoginStub(),
      notificationAuthorization: RecoveryAuthorizationStub()
    )
    var recovered = 0
    model.settingsRecovered = { recovered += 1 }

    model.resetSettings()

    #expect(recovered == 0)
  }

  @Test
  @MainActor
  func followUpRunsUpdateCheckAndLoginRegistration() {
    var checks = 0
    var registrations = 0
    let register: () -> Void = { registrations += 1 }

    let followUp = SettingsRecoveryFollowUp(
      updateCheck: LaunchUpdateCheck(
        settingsError: { nil },
        isEnabled: { true },
        check: { checks += 1 }
      ),
      registerLogin: register
    )
    followUp.run()

    #expect(checks == 1)
    #expect(registrations == 1)
  }
}

private final class RecoveryDeliverySpy: RuntimeNotificationDelivering {
  private(set) var total = 0

  func deliver(title _: String, body _: String, sound _: Bool) { total += 1 }
  nonisolated(nonsending) func deliverAwaitingSystem(
    title _: String,
    body _: String,
    sound _: Bool
  ) async {
    await Task.yield()
    total += 1
  }
}

private final class RecoveryLaunchAtLoginStub: LaunchAtLoginControlling {
  let isAvailable = true
  let isEnabled = false

  func setEnabled(_: Bool) {}
}

private final class RecoveryAuthorizationStub: NotificationAuthorizationControlling,
  @unchecked Sendable
{
  func state() -> RuntimeNotificationAuthorizationState { .notDetermined }

  func request() -> (RuntimeNotificationAuthorizationState, String?) { (.allowed, nil) }

  @MainActor
  func openSystemSettings() {}
}
