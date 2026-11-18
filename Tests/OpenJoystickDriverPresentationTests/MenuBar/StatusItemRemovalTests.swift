import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The user removes the menu bar item.
@Suite
struct StatusItemRemovalTests {
  @MainActor
  private func makeModel(_ settings: SettingsStore) -> SettingsPreferencesModel {
    SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
  }

  @Test
  @MainActor
  func removingItemStoresMenuBarOffAndTurnsDockOn() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = makeModel(settings)
    #expect(model.showInMenuBar && !model.showInDock)

    #expect(model.menuBarItemRemoved())

    #expect(!model.showInMenuBar && model.showInDock)
    #expect(try !settings.value(of: .showInMenuBar))
    #expect(try settings.value(of: .showInDock))
    #expect(model.errorMessage == nil)
  }

  @Test
  @MainActor
  func removingItemKeepsDockOnWhenItOn() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.showInDock, to: true)
    let model = makeModel(settings)

    #expect(model.menuBarItemRemoved())

    #expect(!model.showInMenuBar && model.showInDock)
    #expect(try settings.value(of: .showInDock))
  }

  @Test
  @MainActor
  func removalCannotStoredLeavesSettingsAsThey() throws {
    let root = RootedDataDirectory.temporary()
    let settings = SettingsStore(directory: root)
    let model = makeModel(settings)
    try FileManager.default.createDirectory(
      at: settings.folderURL,
      withIntermediateDirectories: true
    )
    try Data("not a property list".utf8).write(to: settings.userFileURL)

    #expect(!model.menuBarItemRemoved())

    #expect(model.showInMenuBar && !model.showInDock)
    #expect(model.errorMessage != nil)
  }

  @Test
  func fileTurnsBothOffOpensMainWindowAtLaunch() {
    let both = SettingsStoreError.storedNoVisibleEntryPoint(file: "/tmp/Settings.plist")
    #expect(SettingsFileStartup.opensMainWindowAtLaunch(settingsError: both))
    #expect(!SettingsFileStartup.opensMainWindowAtLaunch(settingsError: nil))
    #expect(
      !SettingsFileStartup.opensMainWindowAtLaunch(
        settingsError: .damaged(file: "/tmp/Settings.plist")
      )
    )
  }
}
