#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  struct ProfilesView: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @ObservedObject var navigation: SettingsNavigationModel
    @State private var selectedProfileID: UUID?
    @State private var isCreatingProfile = false
    @State private var profileEditorTransition = ProfileEditorTransitionState()
    @State private var activeAlert: ProfilesAlert?
    @State private var profileActionError: String?
    @State private var observedDiscardGeneration = 0
    @State private var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload?
    @State private var preservedEditorProfile: RemappingProfile?
    @State private var profileEditorGeneration = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        if let profileActionError {
          ProfileActionErrorBanner(message: profileActionError) { self.profileActionError = nil }
        }
        GeometryReader { proxy in
          HStack(spacing: 0) {
            profileList.frame(width: profileListWidth(for: proxy.size.width)).frame(
              maxHeight: .infinity,
              alignment: .topLeading
            )
            Divider()
            profileDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }.sheet(isPresented: $isCreatingProfile) {
        ProfileNameSheet(
          title: OJDLocalized.string("profiles.new", fallback: "New profile"),
          initialName: OJDLocalized.string("profiles.defaultName", fallback: "My controller"),
          devices: connectedDevices
        ) { name, device, scope in createProfile(named: name, for: device, scope: scope) }
      }.alert(item: $activeAlert) { alert in
        switch alert {
        case .delete(let id):
          Alert(
            title: Text(OJDLocalized.string("profiles.deleteTitle", fallback: "Delete profile?")),
            message: Text(
              OJDLocalized.string(
                "profiles.deleteMessage",
                fallback: "This removes the profile from OpenJoystickDriver."
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("common.delete", fallback: "Delete"))
            ) { deleteProfile(id) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .discard:
          Alert(
            title: Text(
              OJDLocalized.string("settings.discardTitle", fallback: "Discard unsaved changes?")
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.discardMessage",
                fallback: "Your changes to this profile have not been saved."
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("settings.discardAction", fallback: "Discard Changes"))
            ) {
              guard let action = profileEditorTransition.discardPendingAction() else {
                activeAlert = nil
                return
              }
              setEditorDirty(false)
              activeAlert = nil
              performProfileAction(action)
            },
            secondaryButton: .cancel { cancelPendingProfileAction() }
          )
        }
      }.onAppear {
        if case .available(let snapshot) = viewModel.remappingState { lastKnownSnapshot = snapshot }
        if observedDiscardGeneration != navigation.discardGeneration {
          profileEditorTransition.setDirty(false)
          observedDiscardGeneration = navigation.discardGeneration
        }
        selectFirstProfileIfNeeded()
        navigation.setProfilesEditorDirty(editorHasUnsavedChanges)
        handleProfileMutation(viewModel.mutationState)
      }.onReceive(viewModel.$mutationState) { handleProfileMutation($0) }.onReceive(
        navigation.$discardGeneration
      ) { generation in
        observedDiscardGeneration = generation
        if editorHasUnsavedChanges { setEditorDirty(false) }
      }.onReceive(viewModel.$remappingState) { state in
        if case .available(let snapshot) = state {
          if !editorHasUnsavedChanges, let selectedProfileID,
            lastKnownSnapshot?.profiles.first(where: { $0.id == selectedProfileID })
              != snapshot.profiles.first(where: { $0.id == selectedProfileID })
          {
            profileEditorGeneration += 1
          }
          if editorHasUnsavedChanges, let selectedProfileID,
            !snapshot.profiles.contains(where: { $0.id == selectedProfileID }),
            let previous = lastKnownSnapshot?.profiles.first(where: { $0.id == selectedProfileID })
          {
            preservedEditorProfile = previous
          }
          lastKnownSnapshot = snapshot
          selectFirstProfileIfNeeded()
        }
      }
    }

    private var profiles: [RemappingProfile] {
      switch viewModel.remappingState {
      case .available(let snapshot): return snapshot.profiles
      case .loading, .unavailable, .error: return lastKnownSnapshot?.profiles ?? []
      }
    }

    private func profileListWidth(for availableWidth: CGFloat) -> CGFloat {
      min(220, max(168, availableWidth * 0.25))
    }

    private var selectedProfile: RemappingProfile? {
      if let selectedProfileID {
        if let current = profiles.first(where: { $0.id == selectedProfileID }) { return current }
        if let preservedEditorProfile, preservedEditorProfile.id == selectedProfileID {
          return preservedEditorProfile
        }
      }
      return profiles.first
    }

    private var profileList: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(OJDLocalized.string("common.profiles", fallback: "Profiles")).font(.headline)
          Spacer()
          Button(
            action: { isCreatingProfile = true },
            label: {
              OJDSystemSymbol(name: "plus", fallback: "+").ojdAccessibilityLabel(
                OJDLocalized.string("profiles.new", fallback: "New profile")
              ).frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
            }
          ).buttonStyle(BorderlessButtonStyle()).disabled(isProfileActionBlocked)
          Button(action: importProfile) {
            OJDSystemSymbol(name: "square.and.arrow.down", fallback: "Import")
              .ojdAccessibilityLabel(
                OJDLocalized.string("profiles.import", fallback: "Import profile")
              ).frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
          }.buttonStyle(BorderlessButtonStyle()).disabled(isProfileActionBlocked)
        }.padding(.horizontal, 14).padding(.top, 18)

        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("profiles.loading", fallback: "Loading profiles...")
          ).padding(.horizontal, 14)
        case .unavailable(let message), .error(let message):
          VStack(alignment: .leading, spacing: 6) {
            Text(
              OJDLocalized.string("profiles.loadError", fallback: "Profiles could not be loaded.")
            ).font(.caption.weight(.semibold))
            Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
            Button(
              OJDLocalized.string("common.tryAgain", fallback: "Try again"),
              action: refreshProfiles
            )
          }.padding(.horizontal, 14)
        case .available: if !profiles.isEmpty { profileListRows }
        }
        Spacer(minLength: 0)
      }.background(Color(NSColor.controlBackgroundColor))
    }

    private var profileListRows: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(profiles) { profile in
            Button(
              action: { selectProfile(profile.id) },
              label: {
                HStack(spacing: 8) {
                  OJDSystemSymbol(
                    name: isActive(profile) ? "checkmark.circle.fill" : "circle",
                    fallback: isActive(profile)
                      ? OJDLocalized.string("profiles.active", fallback: "Active") : "○"
                  ).foregroundColor(Color(NSColor.controlAccentColor))
                  VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).lineLimit(1)
                    Text(assignmentCountLabel(profile.bindings.count)).font(.caption)
                      .foregroundColor(Color(NSColor.secondaryLabelColor))
                  }
                  Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
              }
            ).buttonStyle(ProfileListButtonStyle(selected: selectedProfile?.id == profile.id))
              .ojdAccessibilityLabel(profile.name).ojdAccessibilitySelection(
                selectedProfile?.id == profile.id
              ).ojdAccessibilityValue(profileAccessibilityValue(profile))
          }
        }.padding(.horizontal, 8).disabled(isProfileActionBlocked)
      }
    }

    @ViewBuilder private var profileDetail: some View {
      if let selectedProfile {
        VStack(alignment: .leading, spacing: 0) {
          refreshStatus
          ProfileEditorView(
            profile: selectedProfile,
            viewModel: viewModel,
            isActive: isActive(selectedProfile),
            isEditingBlocked: profileEditorTransition.isEditingBlocked,
            onDelete: { activeAlert = .delete(selectedProfile.id) },
            onExport: { exportProfile($0) },
            onEditingStateChanged: { setEditorDirty($0) },
            onMutationStarted: { beginProfileMutation($0) },
            onMutationResult: { handleProfileMutationResult($0) }
          ).id(
            selectedProfile.id.uuidString + "-\(navigation.discardGeneration)"
              + "-\(profileEditorGeneration)"
          )
        }
      } else {
        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("profiles.loading", fallback: "Loading profiles...")
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string("profiles.unavailable", fallback: "Profiles unavailable"),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "profiles.loadError",
              fallback: "Profiles could not be loaded."
            ),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .available: noProfilesState.padding(28)
        }
      }
    }

    private var noProfilesState: some View {
      VStack(alignment: .leading, spacing: 12) {
        EmptyStateView(
          symbol: "plus.circle",
          title: OJDLocalized.string("profiles.none", fallback: "No profiles"),
          message: OJDLocalized.string(
            "profiles.createMessage",
            fallback: "Create a profile to start assigning controls."
          )
        )
        Button(OJDLocalized.string("profiles.create", fallback: "Create profile...")) {
          isCreatingProfile = true
        }.disabled(isProfileActionBlocked)
      }
    }

    private func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("profiles.assignments", count: count, fallback: "%d assignments")
    }

    private func profileAccessibilityValue(_ profile: RemappingProfile) -> String {
      let count = assignmentCountLabel(profile.bindings.count)
      guard isActive(profile) else { return count }
      return OJDLocalized.formatted("profiles.activeAssignmentCount", fallback: "%@, active", count)
    }

    @ViewBuilder private var refreshStatus: some View {
      switch viewModel.remappingState {
      case .loading:
        HStack(spacing: 8) {
          OJDLoadingIndicator()
          Text(OJDLocalized.string("profiles.refreshing", fallback: "Refreshing profile state..."))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(.horizontal, 28).padding(.top, 14)
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "profiles.stateUnavailable",
            fallback: "Profile state is unavailable"
          ),
          message: OJDLocalized.formatted(
            "profiles.draftPreserved",
            fallback: "Your current draft is preserved. %@",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .error(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "profiles.refreshError",
            fallback: "Could not refresh profile state"
          ),
          message: OJDLocalized.formatted(
            "profiles.draftPreserved",
            fallback: "Your current draft is preserved. %@",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .available: EmptyView()
      }
    }

    private func selectFirstProfileIfNeeded() {
      if selectedProfileID == nil { selectedProfileID = profiles.first?.id }
    }

    private func refreshProfiles() { Task { @MainActor in await viewModel.refresh() } }

    private func selectProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      requestProfileAction(.select(profileID))
    }

    private func setEditorDirty(_ dirty: Bool) {
      profileEditorTransition.setDirty(dirty)
      if !dirty { preservedEditorProfile = nil }
      navigation.setProfilesEditorDirty(dirty)
    }

    private var editorHasUnsavedChanges: Bool { profileEditorTransition.isDirty }

    private func requestProfileAction(_ action: ProfileEditorAction) {
      guard !isProfileActionBlocked else { return }
      switch profileEditorTransition.request(action) {
      case .perform(let action): performProfileAction(action)
      case .confirmDiscard: activeAlert = .discard(action.profileID)
      case .blocked: break
      }
    }

    private func performProfileAction(_ action: ProfileEditorAction) {
      guard !isProfileActionBlocked else { return }
      switch action {
      case .select(let profileID):
        preservedEditorProfile = nil
        selectedProfileID = profileID
      case .importProfile(let profile):
        let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
        guard beginProfileMutation(request) else { return }
        Task { @MainActor in
          let result = await viewModel.importRemappingProfile(profile, request: request)
          handleProfileMutationResult(result)
        }
      }
    }

    private func selectCompletedProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      preservedEditorProfile = nil
      selectedProfileID = profileID
    }

    private func cancelPendingProfileAction() {
      profileEditorTransition.cancelPendingAction()
      activeAlert = nil
    }

    private func isActive(_ profile: RemappingProfile) -> Bool {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      switch viewModel.remappingState {
      case .available(let current): snapshot = current
      case .loading, .unavailable, .error: snapshot = lastKnownSnapshot
      }
      guard let snapshot else { return false }
      return snapshot.activeProfiles.contains { $0.profileID == profile.id }
    }

    private func createProfile(
      named name: String,
      for device: RemappingDeviceScope,
      scope: RemappingApplicationScope
    ) {
      guard !isProfileActionBlocked else { return }
      let profile = RemappingProfile(
        name: name,
        device: device,
        applicationScope: scope,
        bindings: []
      )
      let request = RuntimeMutationRequest(operation: .create(profileID: profile.id))
      guard beginProfileMutation(request) else { return }
      Task { @MainActor in
        let result = await viewModel.createRemappingProfile(profile, request: request)
        handleProfileMutationResult(result)
      }
    }

    private func deleteProfile(_ profileID: UUID) {
      guard !isProfileActionBlocked else { return }
      activeAlert = nil
      let restoreDirtyStateOnFailure = selectedProfileID == profileID && editorHasUnsavedChanges
      let request = RuntimeMutationRequest(operation: .delete(profileID: profileID))
      guard beginProfileMutation(request, restoresDirtyOnFailure: restoreDirtyStateOnFailure) else {
        return
      }
      if selectedProfileID == profileID {
        setEditorDirty(false)
        preservedEditorProfile = nil
      }
      Task { @MainActor in
        let result = await viewModel.deleteRemappingProfile(id: profileID, request: request)
        handleProfileMutationResult(result)
      }
    }

    private func importProfile() {
      guard !isProfileActionBlocked else { return }
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = OJDLocalized.string("profiles.import", fallback: "Import profile")
      configureJSONTypes(panel)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        let profile = try RemappingProfileFileStore.load(from: url)
        requestProfileAction(.importProfile(profile))
      } catch { profileActionError = RuntimePresentation.userFacingError(error) }
    }

    private func exportProfile(_ profile: RemappingProfile) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("profiles.export", fallback: "Export profile")
      panel.nameFieldStringValue = "\(profile.name).json"
      configureJSONTypes(panel)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        try RemappingProfileFileStore.write(profile, to: url)
        profileActionError = nil
      } catch { profileActionError = RuntimePresentation.userFacingError(error) }
    }

    private func configureJSONTypes(_ panel: NSSavePanel) {
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [.json]
      } else {
        panel.allowedFileTypes = ["json"]
      }
    }

    private func handleProfileMutation(_ mutation: RuntimeMutationState) {
      reconcileActiveProfileMutation()
      if case .saving = mutation { return }
      guard let operation = viewModel.lastMutationOperation,
        let mutationID = viewModel.lastMutationID
      else { return }
      let request = RuntimeMutationRequest(operation: operation, id: mutationID)
      switch mutation {
      case .succeeded, .completed:
        handleProfileMutationResult(.succeeded(id: request.id, operation: request.operation))
      case .error(let message):
        handleProfileMutationResult(
          .failed(id: request.id, operation: request.operation, message: message)
        )
      case .conflict:
        handleProfileMutationResult(.conflict(id: request.id, operation: request.operation))
      default: break
      }
    }

    private func handleProfileMutationResult(_ result: RuntimeMutationResult) {
      switch result {
      case .succeeded(let mutationID, let operation):
        let finish = finishProfileMutation(
          RuntimeMutationRequest(operation: operation, id: mutationID),
          succeeded: true
        )
        guard finish.didRelease else { return }
        profileActionError = nil
        switch operation {
        case .create, .importProfile:
          switch ProfileEditorMutationCompletion.action(
            for: operation,
            selectedProfileID: selectedProfileID,
            shouldRefreshEditor: finish.shouldRefreshEditor
          ) {
          case .none: break
          case .select(let profileID): selectCompletedProfile(profileID)
          case .refreshEditor: profileEditorGeneration += 1
          }
        case .delete(let profileID) where selectedProfileID == profileID:
          selectedProfileID = profiles.first?.id
        default: break
        }
      case .conflict(let mutationID, let operation):
        _ = finishProfileMutation(
          RuntimeMutationRequest(operation: operation, id: mutationID),
          succeeded: false
        )
        if isProfileAction(operation) {
          profileActionError =
            viewModel.lastError
            ?? OJDLocalized.string(
              "profiles.actionError",
              fallback: "This profile action could not be completed. Try again."
            )
        }
      case .failed(let mutationID, let operation, let message),
        .rejected(let mutationID, let operation, let message):
        _ = finishProfileMutation(
          RuntimeMutationRequest(operation: operation, id: mutationID),
          succeeded: false
        )
        if isProfileAction(operation) { profileActionError = message }
      }
    }

    private func finishProfileMutation(_ request: RuntimeMutationRequest, succeeded: Bool)
      -> ProfileEditorMutationFinish
    {
      guard profileEditorTransition.ownsMutation(request) else { return .ignored }
      guard navigation.ownsProfilesEditorMutation(request) else { return .ignored }
      let finish = profileEditorTransition.finishMutationIfOwned(request, succeeded: succeeded)
      guard finish.didRelease else { return .ignored }
      guard navigation.finishProfilesEditorMutation(request) else { return .ignored }
      navigation.setProfilesEditorDirty(editorHasUnsavedChanges)
      return finish
    }

    private func beginProfileMutation(
      _ request: RuntimeMutationRequest,
      restoresDirtyOnFailure: Bool = false
    ) -> Bool {
      let start = profileEditorTransition.beginMutation(
        request,
        restoresDirtyOnFailure: restoresDirtyOnFailure
      )
      guard start == .acquired else { return false }
      if !navigation.ownsProfilesEditorMutation(request),
        !navigation.beginProfilesEditorMutation(request)
      {
        _ = profileEditorTransition.finishMutationIfOwned(request)
        return false
      }
      return true
    }

    private func reconcileActiveProfileMutation() {
      guard let operation = viewModel.activeMutationOperation,
        let mutationID = viewModel.activeMutationID
      else { return }
      _ = reconcileProfileMutation(RuntimeMutationRequest(operation: operation, id: mutationID))
    }

    private func reconcileProfileMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard navigation.reconcileProfilesEditorMutation(request) else { return false }
      return profileEditorTransition.reconcileRuntimeMutation(request).isAccepted
    }

    private func isProfileAction(_ operation: RuntimeMutationOperation) -> Bool {
      switch operation {
      case .create, .delete, .activate, .deactivate, .importProfile: return true
      case .update: return false
      }
    }

    private var isMutationActive: Bool {
      viewModel.activeMutationOperation != nil || profileEditorTransition.isEditingBlocked
    }

    private var isProfileActionBlocked: Bool {
      isMutationActive || profileEditorTransition.isEditingBlocked
    }

    private var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }
  }

  private enum ProfilesAlert: Identifiable {
    case delete(UUID)
    case discard(UUID)

    var id: String {
      switch self {
      case .delete(let profileID): return "delete-\(profileID.uuidString)"
      case .discard(let profileID): return "discard-\(profileID.uuidString)"
      }
    }
  }

#endif
