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
        onMutationResult: { _ in }
      )
      return (view, model)
    }

    @Test
    func anEditWhileTheEditorIsOnHoldSaysWhy() {
      let (view, model) = Self.editor(isEditingBlocked: true)
      view.removeAllAssignments()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
      model.localError = nil
      view.updateMetadata(model.expectedCurrent)
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func anEditWhileASaveRunsSaysSo() {
      let (view, model) = Self.editor()
      let request = RuntimeMutationRequest(operation: .update(profileID: view.profile.id))
      let began = model.saveState.begin(request)
      #expect(began)
      #expect(view.editingBlock == .saving)
      view.restoreDefaultInput()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedSaving"))
    }

    @Test
    func anActivationWhileEditingIsOnHoldSaysWhy() {
      let (view, model) = Self.editor(isEditingBlocked: true)
      view.activateProfile(allowEmpty: false)
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func aSaveThatTheListRefusesSaysSo() {
      let (view, model) = Self.editor(
        draftProfile: makeProfile().replacing(name: "Changed"),
        onMutationStarted: { _ in false }
      )
      view.save()
      #expect(model.localError == OJDLocalized.string("ui.profiles.editBlockedChange"))
      #expect(!view.saveInFlight)
    }

    @Test
    func aSaveWithNothingToSaveLeavesTheSaveButtonUnavailable() {
      let (view, _) = Self.editor()
      #expect(view.saveStatus == .saved)
      #expect(!view.canSave)
    }

    @Test
    func theSaveButtonIsAvailableForUnsavedChangesAndNamesThem() {
      let (view, _) = Self.editor(draftProfile: makeProfile().replacing(name: "Changed"))
      #expect(view.canSave)
      #expect(view.saveStatus == .unsaved)
      #expect(view.saveButtonAccessibilityValue == OJDLocalized.string("ui.profiles.unsaved"))
    }

    @Test
    func aFailedSaveOfUnsavedEditsStillNamesTheUnsavedEdits() {
      let (view, model) = Self.editor(draftProfile: makeProfile().replacing(name: "Changed"))
      model.saveError = "boom"
      #expect(view.saveStatus == .error)
      #expect(view.showsUnsavedAfterFailure)
    }

    @Test
    func theFooterShowsTheBlockReasonWhenNoEditWasTried() {
      let (view, _) = Self.editor(isEditingBlocked: true)
      #expect(view.footerNotice == OJDLocalized.string("ui.profiles.editBlockedHold"))
    }

    @Test
    func choosingAVirtualGamepadWhileExclusiveInputIsOnResetsItAndSaysSo() {
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

    private static func holdARequest(_ screen: ProfilesViewModel) {
      screen.editorTransition.beginMutation(
        RuntimeMutationRequest(operation: .create(profileID: UUID()))
      )
    }

    @Test
    func aProfileActionWhileAChangeRunsShowsTheReasonInTheBanner() {
      let (view, screen) = Self.profilesView(Self.holdARequest)
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
    func theBlockReasonsDifferAndAreText() {
      let messages = [ProfileActionBlock.changeRunning, .recoveryRunning, .needsRecovery]
        .map(\.message)
      #expect(Set(messages).count == 3)
      #expect(!messages.contains { $0.hasPrefix("ui.profiles.") })
    }

    @Test
    func aRequestThatTheMainWindowRefusesShowsTheReason() {
      let (view, screen) = Self.profilesView()
      let held = RuntimeMutationRequest(operation: .create(profileID: UUID()))
      #expect(view.navigation.beginProfilesEditorMutation(held))
      view.createProfile(makeProfile())
      #expect(screen.profileActionError == OJDLocalized.string("ui.profiles.actionBlockedChange"))
    }

    @Test
    func aFreeScreenHasNoBlock() {
      let (view, screen) = Self.profilesView()
      #expect(view.profileActionBlock == nil)
      view.requestProfileAction(.select(UUID()))
      #expect(screen.profileActionError == nil)
    }
  }

#endif
