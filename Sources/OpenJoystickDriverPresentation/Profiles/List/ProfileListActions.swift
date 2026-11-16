#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {
    /// Selects the first profile when none is selected.
    func selectFirstProfileIfNeeded() {
      if selectedProfileID == nil { selectedProfileID = profiles.first?.id }
    }

    /// Asks the runtime to refresh the remapping snapshot.
    func refreshProfiles() { Task { @MainActor in await viewModel.refresh() } }

    /// Selects the profile through the editor's discard check; selecting the selected profile does
    /// nothing.
    ///
    /// - Parameter profileID: The profile to select.
    func selectProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      requestProfileAction(.select(profileID))
    }

    /// Deletes a damaged profile file or resets an unusable library through the service, closes the
    /// alert and shows a failure beside the button.
    ///
    /// - Parameters:
    ///   - issueID: The identifier of the profile issue.
    ///   - resetLibrary: Whether to reset the library instead of deleting the damaged file.
    func recoverProfileIssue(_ issueID: UUID, resetLibrary: Bool) {
      activeAlert = nil
      Task { @MainActor in
        let failure =
          resetLibrary
          ? await library.resetRemappingProfileLibrary(issueID: issueID)
          : await library.deleteDamagedRemappingProfile(issueID: issueID)
        screen.failProfileAction(failure, beside: .recovery)
        if failure == nil {
          selectedRecoveryIssueID = nil
          selectFirstProfileIfNeeded()
        }
      }
    }

    /// Converts the stored documents of an earlier alpha, then refreshes the profiles; a document
    /// that cannot be converted shows beside the Migrate button.
    func migrateStoredDocuments() {
      Task { @MainActor in
        let failed = DocumentMigrator().run(dryRun: false).contains { $0.verdict == .failed }
        await viewModel.refresh()
        screen.failProfileAction(
          failed ? OJDLocalized.string("platform.macos.ui.migrate.failed") : nil,
          beside: .migration
        )
      }
    }

    /// Records whether the editor holds unsaved edits in the screen and the main window.
    ///
    /// A clean editor also drops the profile preserved from a deleted selection.
    ///
    /// - Parameter dirty: Whether the editor holds unsaved edits.
    func setEditorDirty(_ dirty: Bool) {
      profileEditorTransition.setDirty(dirty)
      if !dirty { preservedEditorProfile = nil }
      navigation.setProfilesEditorDirty(dirty)
    }

    /// Whether the editor holds unsaved edits.
    var editorHasUnsavedChanges: Bool { profileEditorTransition.isDirty }

    /// Requests an editor action; it runs at once when the edits are clean, and else the discard
    /// alert asks first.
    ///
    /// Does nothing while profile actions are blocked.
    ///
    /// - Parameter action: The action to request.
    func requestProfileAction(_ action: ProfileEditorAction) {
      guard !refuseProfileAction() else { return }
      switch profileEditorTransition.request(action) {
      case .perform(let action): performProfileAction(action)
      case .confirmDiscard: activeAlert = .discard(action.profileID)
      case .blocked: profileActionError = ProfileActionBlock.changeRunning.message
      }
    }

    /// Runs an editor action: selects the profile, or imports it through the profile library.
    ///
    /// Does nothing while profile actions are blocked.
    ///
    /// - Parameter action: The action to run.
    func performProfileAction(_ action: ProfileEditorAction) {
      guard !refuseProfileAction() else { return }
      switch action {
      case .select(let profileID):
        preservedEditorProfile = nil
        selectedProfileID = profileID
      case .importProfile(let profile):
        let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
        guard beginProfileMutationOrExplain(request) else { return }
        Task { @MainActor in
          let result = await library.importRemappingProfile(profile, request: request)
          handleProfileMutationResult(result)
        }
      }
    }

    /// Selects the profile that a create or import added; selecting the selected profile does
    /// nothing.
    ///
    /// - Parameter profileID: The profile to select.
    func selectCompletedProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      preservedEditorProfile = nil
      selectedProfileID = profileID
    }

    /// Drops the action that waited for the person to confirm discarding the edits, and closes the
    /// alert.
    func cancelPendingProfileAction() {
      profileEditorTransition.cancelPendingAction()
      activeAlert = nil
    }

    /// Returns whether the profile is active in the snapshot that the screen shows.
    func isActive(_ profile: RemappingProfile) -> Bool {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      switch viewModel.remappingState {
      case .available(let current): snapshot = current
      case .loading, .unavailable, .error: snapshot = lastKnownSnapshot
      }
      guard let snapshot else { return false }
      return snapshot.activeProfiles.contains { $0.profileID == profile.id }
    }

    /// Adds `profile` to the library: a profile from the creation sheet, or a copy from the
    /// Duplicate sheet.
    ///
    /// - Parameter profile: The profile to add.
    func createProfile(_ profile: RemappingProfile) {
      guard !refuseProfileAction() else { return }
      let request = RuntimeMutationRequest(operation: .create(profileID: profile.id))
      guard beginProfileMutationOrExplain(request) else { return }
      Task { @MainActor in
        let result = await library.createRemappingProfile(profile, request: request)
        handleProfileMutationResult(result)
      }
    }

    /// Adds the converted profile to the library and, once it is saved, shows what the conversion
    /// left out.
    ///
    /// - Parameter conversion: The conversion that the Convert sheet made.
    func convertProfile(_ conversion: RemappingProfileConversion) {
      guard !refuseProfileAction() else { return }
      let request = RuntimeMutationRequest(operation: .create(profileID: conversion.profile.id))
      guard beginProfileMutationOrExplain(request) else { return }
      Task { @MainActor in
        let result = await library.createRemappingProfile(conversion.profile, request: request)
        handleProfileMutationResult(result)
        if case .succeeded = result {
          screen.conversionReport = ProfileConversionReport(conversion)
        }
      }
    }

    /// Deletes the profile through the profile library after the person confirmed the alert.
    ///
    /// If the deleted profile is the selected one, its unsaved edits are dropped, and they come
    /// back when the delete fails.
    ///
    /// - Parameter profileID: The profile to delete.
    func deleteProfile(_ profileID: UUID) {
      guard !refuseProfileAction() else { return }
      activeAlert = nil
      let restoreDirtyStateOnFailure = selectedProfileID == profileID && editorHasUnsavedChanges
      let request = RuntimeMutationRequest(operation: .delete(profileID: profileID))
      guard
        beginProfileMutationOrExplain(request, restoresDirtyOnFailure: restoreDirtyStateOnFailure)
      else { return }
      if selectedProfileID == profileID {
        setEditorDirty(false)
        preservedEditorProfile = nil
      }
      Task { @MainActor in
        let result = await library.deleteRemappingProfile(id: profileID, request: request)
        handleProfileMutationResult(result)
      }
    }

    /// Asks where to save the profile and writes it there.
    ///
    /// - Parameter profile: The profile to export.
    func exportProfile(_ profile: RemappingProfile) { screen.exportProfile(profile) }

    /// Imports a profile chosen through the screen model, from the Profiles screen or the File
    /// menu.
    ///
    /// An import made while profile actions are blocked shows the import-blocked message instead.
    ///
    /// - Parameter profile: The profile that was read from the chosen file.
    func receiveChosenImportProfile(_ profile: RemappingProfile) {
      screen.chosenImportProfile = nil
      guard !isProfileActionBlocked else {
        profileActionError = OJDLocalized.string("ui.profiles.importBlocked")
        return
      }
      requestProfileAction(.importProfile(profile))
    }

    /// Follows the profile library's request state: settles the request in flight with the main
    /// window and the editor, and settles the latest request once its state is not saving.
    ///
    /// - Parameter mutation: The state of the latest request.
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

    /// Settles the result of a profile request.
    ///
    /// A success of a create or an import selects the new profile or refreshes the editor, and a
    /// success of a delete of the selected profile selects the first profile. A conflict, failure
    /// or rejection of a profile action shows its message in the error banner.
    ///
    /// - Parameter result: How the request ended.
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
              "ui.profiles.actionError"
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

    /// Releases the main window's and the editor's ownership of a request that ended.
    ///
    /// - Parameters:
    ///   - request: The request that ended.
    ///   - succeeded: Whether it succeeded.
    /// - Returns: Whether this screen owned the request and what to do with the editor.
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

    /// Takes the main window's and the editor's ownership of a request.
    ///
    /// - Parameters:
    ///   - request: The request to start.
    ///   - restoresDirtyOnFailure: Whether a failure brings the unsaved edits back.
    /// - Returns: Whether the screen may start the request.
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

    /// Settles the request that the profile library reports as in flight, if there is one.
    func reconcileActiveProfileMutation() {
      guard let operation = library.activeMutationOperation,
        let mutationID = library.activeMutationID
      else { return }
      _ = reconcileProfileMutation(RuntimeMutationRequest(operation: operation, id: mutationID))
    }

    /// Settles a request that the profile library reports against what the main window and the
    /// editor own.
    ///
    /// - Parameter request: The request in flight.
    /// - Returns: Whether both accept it.
    func reconcileProfileMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard navigation.reconcileProfilesEditorMutation(request) else { return false }
      return profileEditorTransition.reconcileRuntimeMutation(request).isAccepted
    }

    /// Returns whether the operation is a profile action: not an update from the editor.
    func isProfileAction(_ operation: RuntimeMutationOperation) -> Bool {
      switch operation {
      case .create, .delete, .activate, .deactivate, .importProfile: return true
      case .update: return false
      }
    }

    /// Whether a request runs or the editor is blocked.
    var isMutationActive: Bool {
      library.activeMutationOperation != nil || profileEditorTransition.isEditingBlocked
    }

    /// Why profile creation, import, delete and the like must wait, or nil.
    var profileActionBlock: ProfileActionBlock? {
      screen.actionBlock(library: library, runtime: viewModel)
    }

    /// Whether profile creation, import, delete and the like must wait.
    var isProfileActionBlocked: Bool { profileActionBlock != nil }

    /// Shows the reason profile actions must wait in the error banner and returns whether they do.
    func refuseProfileAction() -> Bool {
      guard let profileActionBlock else { return false }
      profileActionError = profileActionBlock.message
      return true
    }

    /// Takes the ownership of a request, or says that another change holds it.
    func beginProfileMutationOrExplain(
      _ request: RuntimeMutationRequest,
      restoresDirtyOnFailure: Bool = false
    ) -> Bool {
      guard beginProfileMutation(request, restoresDirtyOnFailure: restoresDirtyOnFailure) else {
        profileActionError = ProfileActionBlock.changeRunning.message
        return false
      }
      return true
    }

    /// Whether the snapshot lists damaged profiles or an unusable library.
    var profileLibraryNeedsRecovery: Bool { !(currentSnapshot?.profileIssues.isEmpty ?? true) }

    /// The connected controllers, or none while the status is not loaded.
    var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }
  }

  /// The alerts of the Profiles screen.
  enum ProfilesAlert: Identifiable {
    /// Asks to delete the profile.
    case delete(UUID)
    /// Asks to discard the unsaved edits.
    case discard(UUID)
    /// Asks to delete the damaged profile file of the issue.
    case deleteDamagedProfile(UUID)
    /// Asks to reset the library of the issue.
    case resetLibrary(UUID)

    /// A string that tells the alerts apart, including the profile or issue.
    var id: String {
      switch self {
      case .delete(let profileID): return "delete-\(profileID.uuidString)"
      case .discard(let profileID): return "discard-\(profileID.uuidString)"
      case .deleteDamagedProfile(let issueID): return "delete-damaged-\(issueID.uuidString)"
      case .resetLibrary(let issueID): return "reset-library-\(issueID.uuidString)"
      }
    }
  }

  /// What the profile list has selected.
  enum ProfileListSelection: Hashable {
    /// A profile.
    case profile(UUID)
    /// A damaged profile or unusable library.
    case issue(UUID)
  }

#endif
