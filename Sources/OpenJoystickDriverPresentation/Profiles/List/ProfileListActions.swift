#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {
    func selectFirstProfileIfNeeded() {
      if selectedProfileID == nil { selectedProfileID = profiles.first?.id }
    }

    func refreshProfiles() { Task { @MainActor in await viewModel.refresh() } }

    func selectProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      requestProfileAction(.select(profileID))
    }

    func recoverProfileIssue(_ issueID: UUID, resetLibrary: Bool) {
      activeAlert = nil
      Task { @MainActor in
        profileActionError =
          resetLibrary
          ? await library.resetRemappingProfileLibrary(issueID: issueID)
          : await library.deleteDamagedRemappingProfile(issueID: issueID)
        if profileActionError == nil {
          selectedRecoveryIssueID = nil
          selectFirstProfileIfNeeded()
        }
      }
    }

    func setEditorDirty(_ dirty: Bool) {
      profileEditorTransition.setDirty(dirty)
      if !dirty { preservedEditorProfile = nil }
      navigation.setProfilesEditorDirty(dirty)
    }

    var editorHasUnsavedChanges: Bool { profileEditorTransition.isDirty }

    func requestProfileAction(_ action: ProfileEditorAction) {
      guard !isProfileActionBlocked else { return }
      switch profileEditorTransition.request(action) {
      case .perform(let action): performProfileAction(action)
      case .confirmDiscard: activeAlert = .discard(action.profileID)
      case .blocked: break
      }
    }

    func performProfileAction(_ action: ProfileEditorAction) {
      guard !isProfileActionBlocked else { return }
      switch action {
      case .select(let profileID):
        preservedEditorProfile = nil
        selectedProfileID = profileID
      case .importProfile(let profile):
        let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
        guard beginProfileMutation(request) else { return }
        Task { @MainActor in
          let result = await library.importRemappingProfile(profile, request: request)
          handleProfileMutationResult(result)
        }
      }
    }

    func selectCompletedProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      preservedEditorProfile = nil
      selectedProfileID = profileID
    }

    func cancelPendingProfileAction() {
      profileEditorTransition.cancelPendingAction()
      activeAlert = nil
    }

    func isActive(_ profile: RemappingProfile) -> Bool {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      switch viewModel.remappingState {
      case .available(let current): snapshot = current
      case .loading, .unavailable, .error: snapshot = lastKnownSnapshot
      }
      guard let snapshot else { return false }
      return snapshot.activeProfiles.contains { $0.profileID == profile.id }
    }

    func createProfile(
      named name: String,
      for device: RemappingDeviceScope,
      scope: RemappingApplicationScope
    ) {
      guard !isProfileActionBlocked else { return }
      let profile = RemappingProfile(
        name: name,
        device: device,
        applicationScope: scope,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
        bindings: []
      )
      let request = RuntimeMutationRequest(operation: .create(profileID: profile.id))
      guard beginProfileMutation(request) else { return }
      Task { @MainActor in
        let result = await library.createRemappingProfile(profile, request: request)
        handleProfileMutationResult(result)
      }
    }

    func deleteProfile(_ profileID: UUID) {
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
        let result = await library.deleteRemappingProfile(id: profileID, request: request)
        handleProfileMutationResult(result)
      }
    }

    func importProfile() {
      guard !isProfileActionBlocked else { return }
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = OJDLocalized.string("profiles.import")
      configureJSONTypes(panel)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          let profile = try await screen.documents.load(from: url)
          requestProfileAction(.importProfile(profile))
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    func exportProfile(_ profile: RemappingProfile) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("profiles.export")
      panel.nameFieldStringValue = "\(profile.name).json"
      configureJSONTypes(panel)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          try await screen.documents.write(profile, to: url)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    func configureJSONTypes(_ panel: NSSavePanel) {
      panel.allowedContentTypes = [.json]
    }

    func handleProfileMutation(_ mutation: RuntimeMutationState) {
      reconcileActiveProfileMutation()
      if case .saving = mutation { return }
      guard let operation = library.lastMutationOperation, let mutationID = library.lastMutationID
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

    func handleProfileMutationResult(_ result: RuntimeMutationResult) {
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
            library.lastError
            ?? OJDLocalized.string(
              "profiles.actionError"
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

    func finishProfileMutation(
      _ request: RuntimeMutationRequest,
      succeeded: Bool
    ) -> ProfileEditorMutationFinish {
      guard profileEditorTransition.ownsMutation(request) else { return .ignored }
      guard navigation.ownsProfilesEditorMutation(request) else { return .ignored }
      let finish = profileEditorTransition.finishMutationIfOwned(request, succeeded: succeeded)
      guard finish.didRelease else { return .ignored }
      guard navigation.finishProfilesEditorMutation(request) else { return .ignored }
      navigation.setProfilesEditorDirty(editorHasUnsavedChanges)
      return finish
    }

    func beginProfileMutation(
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

    func reconcileActiveProfileMutation() {
      guard let operation = library.activeMutationOperation,
        let mutationID = library.activeMutationID
      else { return }
      _ = reconcileProfileMutation(RuntimeMutationRequest(operation: operation, id: mutationID))
    }

    func reconcileProfileMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard navigation.reconcileProfilesEditorMutation(request) else { return false }
      return profileEditorTransition.reconcileRuntimeMutation(request).isAccepted
    }

    func isProfileAction(_ operation: RuntimeMutationOperation) -> Bool {
      switch operation {
      case .create, .delete, .activate, .deactivate, .importProfile: return true
      case .update: return false
      }
    }

    var isMutationActive: Bool {
      library.activeMutationOperation != nil || profileEditorTransition.isEditingBlocked
    }

    var isProfileActionBlocked: Bool {
      isMutationActive || profileEditorTransition.isEditingBlocked
        || library.profileRecoveryInFlight || profileLibraryNeedsRecovery
    }

    var profileLibraryNeedsRecovery: Bool { !(currentSnapshot?.profileIssues.isEmpty ?? true) }

    var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }
  }

  enum ProfilesAlert: Identifiable {
    case delete(UUID)
    case discard(UUID)
    case deleteDamagedProfile(UUID)
    case resetLibrary(UUID)

    var id: String {
      switch self {
      case .delete(let profileID): return "delete-\(profileID.uuidString)"
      case .discard(let profileID): return "discard-\(profileID.uuidString)"
      case .deleteDamagedProfile(let issueID): return "delete-damaged-\(issueID.uuidString)"
      case .resetLibrary(let issueID): return "reset-library-\(issueID.uuidString)"
      }
    }
  }

  enum ProfileListSelection: Hashable {
    case profile(UUID)
    case issue(UUID)
  }

#endif
