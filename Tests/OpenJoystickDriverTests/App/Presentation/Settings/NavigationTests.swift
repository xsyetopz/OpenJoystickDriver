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

  @Test @MainActor func activeProfileMutationKeepsTheProfilesPaneMountedUntilResolution() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let persistence = UserDefaultsSettingsPanePersistence(defaults: defaults)

    let navigation = SettingsNavigationModel(persistence: persistence)
    let request = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    navigation.requestPane(.profiles)
    navigation.setProfilesEditorDirty(true)
    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(false)

    navigation.requestPane(.settings)

    #expect(navigation.selectedPane == .profiles)
    #expect(navigation.pendingPane == nil)
    #expect(!navigation.isDiscardConfirmationPresented)

    #expect(navigation.finishProfilesEditorMutation(request))
    navigation.setProfilesEditorDirty(true)
    navigation.requestPane(.settings)

    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)

    navigation.cancelPendingPane()
    navigation.setProfilesEditorDirty(false)
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test @MainActor func overlappingProfileMutationCannotReleaseTheFirstNavigationOwner() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )
    let first = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    let second = RuntimeMutationRequest(operation: .importProfile(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(first))
    #expect(!navigation.beginProfilesEditorMutation(second))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(!navigation.finishProfilesEditorMutation(second))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(navigation.finishProfilesEditorMutation(first))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test @MainActor func matchingPreflightFailureReleasesNavigationOwner() {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )
    let request = RuntimeMutationRequest(operation: .update(profileID: UUID()))

    #expect(navigation.beginProfilesEditorMutation(request))
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == nil)

    #expect(
      !navigation.finishProfilesEditorMutation(RuntimeMutationRequest(operation: request.operation))
    )
    #expect(navigation.ownsProfilesEditorMutation(request))
    #expect(navigation.finishProfilesEditorMutation(request))

    navigation.setProfilesEditorDirty(false)
    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .settings)
  }

  @Test @MainActor func preflightFailureReleasesBothOwnersAndPreservesDirtyDraft() async {
    let suiteName = "SettingsNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      #expect(Bool(false), "Could not create isolated UserDefaults suite")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let original = makeProfile(name: "Original")
    let invalid = makeProfile(id: original.id, name: "")
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let viewModel = RuntimeViewModel(gateway: gateway)
    var transition = ProfileEditorTransitionState()
    let navigation = SettingsNavigationModel(
      persistence: UserDefaultsSettingsPanePersistence(defaults: defaults)
    )

    transition.setDirty(true)
    #expect(transition.beginMutation(request) == .acquired)
    #expect(navigation.beginProfilesEditorMutation(request))

    let result = await viewModel.updateRemappingProfile(
      invalid,
      expectedCurrent: original,
      request: request
    )
    #expect(result.request == request)
    #expect(transition.finishMutationIfOwned(result.request, succeeded: false).didRelease)
    #expect(navigation.finishProfilesEditorMutation(result.request))
    navigation.setProfilesEditorDirty(transition.isDirty)

    navigation.requestPane(.settings)
    #expect(navigation.selectedPane == .overview)
    #expect(navigation.pendingPane == .settings)
    #expect(navigation.isDiscardConfirmationPresented)
    #expect(transition.isDirty)
  }
}
