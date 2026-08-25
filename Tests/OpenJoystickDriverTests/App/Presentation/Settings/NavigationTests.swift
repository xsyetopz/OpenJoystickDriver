import Foundation
import Testing

@testable import OpenJoystickDriver

@Suite struct SettingsNavigationTests {
  @Test func everySettingsPaneRemainsInThePrimaryRail() {
    #expect(SettingsPane.primaryCases == SettingsPane.allCases)
    #expect(SettingsPane.primaryCases == [.overview, .controllers, .profiles, .console, .settings])
  }

  @Test @MainActor func restoresTheLastAcceptedPane() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let initial = SettingsNavigationModel(persistence: persistence)
    #expect(initial.selectedPane == .overview)
    initial.requestPane(.profiles)
    #expect(initial.selectedPane == .profiles)

    let restored = SettingsNavigationModel(persistence: persistence)
    #expect(restored.selectedPane == .profiles)
  }

  @Test @MainActor func dirtySelectionPersistsOnlyAfterDiscard() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    navigation.requestPane(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.settings)

    #expect(navigation.selectedPane == .controllers)
    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)
    let beforeDiscard = SettingsNavigationModel(persistence: persistence)
    #expect(beforeDiscard.selectedPane == .controllers)

    navigation.discardPendingPane()
    #expect(navigation.selectedPane == .settings)
    #expect(navigation.pendingPane == nil)
    #expect(!navigation.isDiscardConfirmationPresented)
    let afterDiscard = SettingsNavigationModel(persistence: persistence)
    #expect(afterDiscard.selectedPane == .settings)
  }

  @Test @MainActor func canceledDirtySelectionLeavesThePersistedPaneUnchanged() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    navigation.requestPane(.controllers)
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.console)
    navigation.cancelPendingPane()

    #expect(navigation.selectedPane == .controllers)
    #expect(navigation.pendingPane == nil)
    let restored = SettingsNavigationModel(persistence: persistence)
    #expect(restored.selectedPane == .controllers)
  }
}
