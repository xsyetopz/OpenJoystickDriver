import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct InterfaceLevelPreferencesTests {
  @MainActor
  private func makeModel(_ directory: RootedDataDirectory) -> SettingsPreferencesModel {
    SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: SettingsStore(directory: directory),
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
  }

  @Test
  @MainActor
  func theInterfaceLevelStartsAsTheDefault() {
    #expect(makeModel(RootedDataDirectory.temporary()).interfaceLevel == InterfaceLevel.default)
  }

  @Test(arguments: InterfaceLevel.allCases)
  @MainActor
  func theSetterPersistsTheLevel(level: InterfaceLevel) throws {
    let directory = RootedDataDirectory.temporary()
    let model = makeModel(directory)

    model.setInterfaceLevel(level)

    #expect(model.interfaceLevel == level)
    #expect(try SettingsStore(directory: directory).interfaceLevel() == level)
  }

  @Test
  @MainActor
  func theSetterPublishesTheLevel() {
    let model = makeModel(RootedDataDirectory.temporary())
    var published: [InterfaceLevel] = []
    let subscription = model.$interfaceLevel.sink { published.append($0) }

    model.setInterfaceLevel(.advanced)
    model.setInterfaceLevel(.simple)

    #expect(published == [.simple, .advanced, .simple])
    subscription.cancel()
  }

  @Test
  @MainActor
  func aStoredLevelShowsAtStartup() throws {
    let directory = RootedDataDirectory.temporary()
    try SettingsStore(directory: directory).setInterfaceLevel(.advanced)

    #expect(makeModel(directory).interfaceLevel == .advanced)
  }

  @Test
  @MainActor
  func aChangeFromAnotherStoreReachesTheModel() async throws {
    let directory = RootedDataDirectory.temporary()
    let model = makeModel(directory)
    #expect(model.interfaceLevel == .simple)

    // What `ojd setting set interfaceLevel` or another process does.
    try SettingsStore(directory: directory).setInterfaceLevel(.advanced)

    await waitUntil("the model reloads the interface level") { model.interfaceLevel == .advanced }
    #expect(model.interfaceLevel == .advanced)
  }
}
