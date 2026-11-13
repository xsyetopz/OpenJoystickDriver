#if canImport(SwiftUI)

  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import SwiftUI
  import Testing

  @testable import OpenJoystickDriverPresentation

  /// Each guard of the profile editor and list gives a reason in words or an unavailable control.
  @Suite
  @MainActor
  struct ProfileGuardReasonTests {
    private static func editor(
      isEditingBlocked: Bool = false,
      draftProfile: RemappingProfile? = nil,
      onMutationStarted: @escaping (RuntimeMutationRequest) -> Bool = { _ in true }
    ) -> (ProfileEditorView, ProfileEditorViewModel) {
      let profile = makeProfile()
      let runtime = RuntimeViewModel(
        gateway: GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
      )
      let model = ProfileEditorViewModel(profile: draftProfile ?? profile)
      model.expectedCurrent = profile
      let ignoreResult: (RuntimeMutationResult) -> Void = { _ in }
      let view = ProfileEditorView(
        profile: profile,
        capabilities: .unknown,
        editor: model,
        viewModel: runtime,
        library: ProfileLibraryModel(runtime: runtime),
        isActive: false,
        isEditingBlocked: isEditingBlocked,
        selectedSection: .constant(.assignments),
        onEditingStateChanged: { _ in },
        onMutationStarted: onMutationStarted,
        onMutationResult: ignoreResult
      )
      return (view, model)
    }

    @Test
    func editWhileEditorOnHoldSaysWhy() {
      let (view, model) = Self.editor(isEditingBlocked: true)
      view.removeAllAssignments()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
      model.localError = nil
      view.updateMetadata(model.expectedCurrent)
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func editWhileSaveRunsSaysSo() {
      let (view, model) = Self.editor()
      let request = RuntimeMutationRequest(operation: .update(profileID: view.profile.id))
      let began = model.saveState.begin(request)
      #expect(began)
      #expect(view.editingBlock == .saving)
      view.restoreDefaultInput()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedSaving"))
    }

    @Test
    func activationWhileEditingOnHoldSaysWhy() {
      let (view, model) = Self.editor(isEditingBlocked: true)
      view.activateProfile(allowEmpty: false)
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func saveListRefusesSaysSo() {
      let (view, model) = Self.editor(
        draftProfile: makeProfile().replacing(name: "Changed")
      ) { _ in false }
      view.save()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedChange"))
      #expect(!view.saveInFlight)
    }

    @Test
    func saveWithNothingToSaveLeavesSaveButtonUnavailable() {
      let (view, _) = Self.editor()
      #expect(view.saveStatus == .saved)
      #expect(!view.canSave)
    }

    @Test
    func saveButtonAvailableForUnsavedChangesAndNamesThem() {
      let (view, _) = Self.editor(draftProfile: makeProfile().replacing(name: "Changed"))
      #expect(view.canSave)
      #expect(view.saveStatus == .unsaved)
      #expect(view.saveButtonAccessibilityValue == OJDLocalized.string("ui.profiles.unsaved"))
    }

    @Test
    func failedSaveOfUnsavedEditsStillNamesUnsavedEdits() {
      let (view, model) = Self.editor(draftProfile: makeProfile().replacing(name: "Changed"))
      model.saveError = "boom"
      #expect(view.saveStatus == .error)
      #expect(view.showsUnsavedAfterFailure)
    }

    @Test
    func footerShowsBlockReasonWhenNoEditTried() {
      let (view, _) = Self.editor(isEditingBlocked: true)
      #expect(view.footerNotice == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func choosingVirtualGamepadWhileExclusiveInputOnResetsItAndSaysSo() {
      let exclusive = RemappingOutputPolicy(virtualGamepad: .disabled, physicalInput: .exclusive)
      #expect(ProfileOutputPolicyView.resetsPhysicalInput(selecting: .mapped, from: exclusive))
      #expect(
        ProfileOutputPolicyView.policy(selecting: .mapped, from: exclusive).physicalInput == .shared
      )
      #expect(!ProfileOutputPolicyView.resetsPhysicalInput(selecting: .disabled, from: exclusive))
      #expect(!ProfileOutputPolicyView.resetsPhysicalInput(selecting: .mapped, from: .systemInput))
    }

    private static func profilesView(
      _ prepare: (ProfilesViewModel) -> Void = { _ in }
    ) -> (ProfilesView, ProfilesViewModel) {
      let profile = makeProfile()
      let runtime = RuntimeViewModel(
        gateway: GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
      )
      let screen = ProfilesViewModel()
      prepare(screen)
      let navigation = MainWindowNavigationModel(
        persistence: UserDefaultsMainWindowAreaPersistence(
          defaults: UserDefaults(suiteName: "ProfileGuardReasonTests.\(UUID().uuidString)")!
        )
      )
      let view = ProfilesView(
        viewModel: runtime,
        library: ProfileLibraryModel(runtime: runtime),
        navigation: navigation,
        screen: screen,
        column: .detail
      )
      return (view, screen)
    }

    private static func holdRequest(_ screen: ProfilesViewModel) {
      screen.editorTransition.beginMutation(
        RuntimeMutationRequest(operation: .create(profileID: UUID()))
      )
    }

    @Test
    func profileActionWhileChangeRunsShowsReasonInBanner() {
      let (view, screen) = Self.profilesView(Self.holdRequest)
      let reason = OJDLocalized.string("ui.profiles.actionBlockedChange")
      #expect(view.profileActionBlock == .changeRunning)
      view.requestProfileAction(.select(UUID()))
      #expect(screen.profileActionError == reason)
      screen.profileActionError = nil
      view.performProfileAction(.select(UUID()))
      #expect(screen.profileActionError == reason)
      screen.profileActionError = nil
      view.createProfile(makeProfile())
      #expect(screen.profileActionError == reason)
      screen.profileActionError = nil
      view.deleteProfile(UUID())
      #expect(screen.profileActionError == reason)
    }

    @Test
    func blockReasonsDifferAndText() {
      let messages = [ProfileActionBlock.changeRunning, .recoveryRunning, .needsRecovery]
        .map(\.message)
      #expect(Set(messages).count == 3)
      #expect(!messages.contains { $0.hasPrefix("ui.profiles.") })
    }

    @Test
    func requestMainWindowRefusesShowsReason() {
      let (view, screen) = Self.profilesView()
      let held = RuntimeMutationRequest(operation: .create(profileID: UUID()))
      #expect(view.navigation.beginProfilesEditorMutation(held))
      view.createProfile(makeProfile())
      #expect(screen.profileActionError == OJDLocalized.string("ui.profiles.actionBlockedChange"))
    }

    @Test
    func freeScreenHasNoBlock() {
      let (view, screen) = Self.profilesView()
      #expect(view.profileActionBlock == nil)
      view.requestProfileAction(.select(UUID()))
      #expect(screen.profileActionError == nil)
    }
  }

#endif
