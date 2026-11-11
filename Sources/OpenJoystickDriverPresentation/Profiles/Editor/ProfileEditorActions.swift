#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {
    /// Adds an assignment to the draft and closes the sheet.
    ///
    /// A refused edit shows in the editor.
    func addBinding(source: RemappingSource, destination: RemappingDestination) {
      guard !refuseEdit() else { return }
      do {
        draft = try draft.addingBinding(source: source, destination: destination)
        activeSheet = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    /// Removes the assignment from the draft.
    func removeBinding(_ id: UUID) {
      guard !refuseEdit() else { return }
      do {
        draft = try draft.removingBinding(id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    /// Sets the axis tuning of the assignment in the draft.
    func updateAxisTuning(_ tuning: RemappingAxisTuning, for id: UUID) {
      guard !refuseEdit() else { return }
      do {
        draft = try draft.settingAxisTuning(tuning, for: id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    /// Replaces the draft with `profile`, the edited details.
    func updateMetadata(_ profile: RemappingProfile) {
      guard !refuseEdit() else { return }
      draft = RuntimeProfileDraft(profile: profile)
      localError = nil
      saveError = nil
      reportEditingState()
    }

    /// The text that says whether the profile is active; a Joy-Con pair profile reads as the state
    /// of its session.
    var activationLabel: String {
      if profile.joyConPair != nil {
        return OJDLocalized.string("ui.profiles.joyConSessionState")
      }
      return OJDLocalized.string(
        isActive ? "ui.profiles.active" : "ui.profiles.notActive"
      )
    }

    /// Returns the text for the number of assignments.
    func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("ui.profiles.assignments", count: count)
    }

    /// The actions of the editor's menu: Restore Default Input while the draft suppresses all
    /// controller input, Remove All Assignments while it has any assignment, Clear Inputs, and
    /// Deactivate All while the profile is active and is not a Joy-Con pair.
    var menuActions: [ProfileEditorMenuAction] {
      var actions: [ProfileEditorMenuAction] = []
      if draft.profile.suppressesAllControllerInput { actions.append(.restoreDefaultInput) }
      let draftProfile = draft.profile
      if !(draftProfile.bindings.isEmpty && draftProfile.chords.isEmpty
        && draftProfile.sequences.isEmpty && draftProfile.layers.isEmpty)
      {
        actions.append(.removeAllAssignments)
      }
      actions.append(.clearInputs)
      if isActive, profile.joyConPair == nil { actions.append(.deactivateAll) }
      return actions
    }

    /// Runs `action`; the ones that change the draft first ask for confirmation.
    func performMenuAction(_ action: ProfileEditorMenuAction) {
      switch action {
      case .details: activeSheet = .metadata
      case .restoreDefaultInput: restoreDefaultInput()
      case .clearInputs: confirmation = .clearInputs
      case .removeAllAssignments: confirmation = .removeAllAssignments
      case .deactivateAll: deactivateAllProfiles()
      }
    }

    /// Sets the draft to the profile with its default input restored.
    func restoreDefaultInput() {
      applyDraftChange { RuntimeProfileDraft(profile: draft.profile.restoringDefaultInput()) }
    }

    /// Removes every assignment, chord, sequence and layer from the draft.
    func removeAllAssignments() {
      applyDraftChange { try draft.removingAllBindings() }
    }

    /// Sets the draft to the profile with all input cleared.
    func clearInputs() {
      applyDraftChange { RuntimeProfileDraft(profile: draft.profile.clearingAllInput()) }
    }

    /// Activates the profile, after the person confirms when it produces no output, launches
    /// actions or needs a permission that is missing.
    func requestActivation() {
      var postEventAccess: RemappingPostEventAccessState?
      if case .available(let state) = viewModel.postEventAccessState { postEventAccess = state }
      if let needed = ProfileEditorConfirmation.activation(
        of: profile,
        postEventAccess: postEventAccess
      ) {
        confirmation = needed
      } else {
        activateProfile(allowEmpty: false)
      }
    }

    /// Activates the profile through the profile library; `allowEmpty` is true only after the
    /// person confirmed that it produces no output.
    ///
    /// Does nothing while another change runs.
    func activateProfile(allowEmpty: Bool) {
      guard !refuseEdit() else { return }
      let request = RuntimeMutationRequest(operation: .activate(profileID: profile.id))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await library.activateRemappingProfile(
          id: profile.id,
          allowEmpty: allowEmpty,
          request: request
        )
        onMutationResult(result)
      }
    }

    /// Deactivates the profile through the profile library.
    ///
    /// Does nothing while another change runs.
    func deactivateProfile() {
      guard !refuseEdit() else { return }
      let request = RuntimeMutationRequest(operation: .deactivate(profileID: profile.id))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await library.deactivateRemappingProfile(
          profileID: profile.id,
          request: request
        )
        onMutationResult(result)
      }
    }

    /// Deactivates the active profile of the profile's controller model.
    ///
    /// Does nothing while another change runs.
    func deactivateAllProfiles() {
      guard !refuseEdit() else { return }
      let request = RuntimeMutationRequest(operation: .deactivate(profileID: nil))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await library.deactivateRemappingProfile(
          vendorID: profile.device.vendorID,
          productID: profile.device.productID,
          request: request
        )
        onMutationResult(result)
      }
    }

    /// Adds a chord to the draft.
    func addChord(
      sources: [RemappingSource],
      mode: RemappingChordMode,
      windowMs: Double,
      destination: RemappingDestination
    ) {
      applyDraftChange {
        try draft.addingChord(
          sources: Set(sources),
          destination: destination,
          mode: mode,
          windowMs: windowMs
        )
      }
    }

    /// Removes the chord from the draft.
    func removeChord(_ id: UUID) { applyDraftChange { try draft.removingChord(id) } }

    /// Adds a sequence to the draft.
    func addSequence(
      sources: [RemappingSource],
      windowMs: Double,
      destination: RemappingDestination
    ) {
      applyDraftChange {
        try draft.addingSequence(sources: sources, windowMs: windowMs, destination: destination)
      }
    }

    /// Removes the sequence from the draft.
    func removeSequence(_ id: UUID) { applyDraftChange { try draft.removingSequence(id) } }

    /// Adds a layer to the draft.
    func addLayer(name: String, activator: RemappingSource, mode: RemappingLayerActivation) {
      applyDraftChange {
        try draft.addingLayer(name: name, activator: activator, activationMode: mode)
      }
    }

    /// Adds the macro to the draft, or replaces the macro with its identifier.
    func saveMacro(_ macro: RemappingMacro) { applyDraftChange { try draft.settingMacro(macro) } }

    /// Removes the macro from the draft.
    func removeMacro(_ id: UUID) { applyDraftChange { try draft.removingMacro(id) } }

    /// Removes the layer from the draft.
    func removeLayer(_ id: UUID) { applyDraftChange { try draft.removingLayer(id) } }

    /// Sets the assignment of `source` in the layer.
    func setLayerBinding(layerID: UUID, source: RemappingSource, destination: RemappingDestination)
    {
      applyDraftChange {
        try draft.settingLayerBinding(layerID: layerID, source: source, destination: destination)
      }
    }

    /// Removes the assignment from the layer.
    func removeLayerBinding(layerID: UUID, bindingID: UUID) {
      applyDraftChange { try draft.removingLayerBinding(layerID: layerID, bindingID: bindingID) }
    }

    /// Sets the axis tuning of a layer assignment.
    func updateLayerAxisTuning(_ tuning: RemappingAxisTuning, layerID: UUID, bindingID: UUID) {
      applyDraftChange {
        try draft.settingLayerBindingAxisTuning(
          layerID: layerID,
          bindingID: bindingID,
          axisTuning: tuning
        )
      }
    }

    /// Replaces the draft with the result of `change` and clears the errors.
    ///
    /// A refused edit shows in the editor and leaves the draft as it is. Does nothing while editing
    /// is disabled.
    func applyDraftChange(_ change: () throws -> RuntimeProfileDraft) {
      guard !refuseEdit() else { return }
      do {
        draft = try change()
        localError = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    /// Saves the draft through the profile library.
    ///
    /// The result is reconciled when the request returns and when the library reports the change.
    /// Does nothing while the draft equals the stored profile, where the Save button is unavailable;
    /// while a save runs or editing is disabled, it shows the reason.
    func save() {
      guard canSave, !refuseEdit() else { return }
      let operation = RuntimeMutationOperation.update(profileID: profile.id)
      let request = RuntimeMutationRequest(operation: operation)
      guard saveState.begin(request) else {
        localError = ProfileEditingBlock.saving.message
        return
      }
      saveError = nil
      localError = nil
      guard onMutationStarted(request) else {
        finishSave()
        localError = ProfileEditingBlock.changeRunning.message
        return
      }
      reportEditingState()
      Task { @MainActor in
        let result = await library.updateRemappingProfile(
          draft.profile,
          expectedCurrent: expectedCurrent,
          request: request
        )
        reconcileSave(request: request, result: result)
        onMutationResult(result)
      }
    }

    /// Tells the profiles list whether the editor holds unsaved edits or a save runs.
    func reportEditingState() {
      onEditingStateChanged(saveInFlight || draft.profile != expectedCurrent)
    }

    /// Takes the library's report of the save in flight: a conflict, an error or the success of
    /// this profile's update.
    ///
    /// A report of any other change is ignored.
    func handleMutation(_ mutation: RuntimeMutationState) {
      guard saveInFlight, pendingUpdateOperation == .update(profileID: profile.id),
        library.lastMutationOperation == pendingUpdateOperation,
        library.lastMutationID == pendingUpdateMutationID
      else { return }

      switch mutation {
      case .conflict(let profileID) where profileID == profile.id: applySaveConflict()
      case .error(let message):
        finishSave()
        localError = message
        saveError = message
      case .succeeded(let profileID) where profileID == profile.id: applySaveSuccess()
      default: return
      }
      reportEditingState()
    }

    /// Ends the save in flight.
    func finishSave() { saveState.cancel() }

    /// Takes the result of the save request that is in flight; the result of any other request is
    /// ignored.
    func reconcileSave(request: RuntimeMutationRequest, result: RuntimeMutationResult) {
      guard saveInFlight, pendingUpdateOperation == request.operation,
        pendingUpdateMutationID == request.id
      else { return }
      switch saveState.resolve(result) {
      case .succeeded: applySaveSuccess()
      case .conflict: applySaveConflict()
      case .failed(let message):
        finishSave()
        localError = message
        saveError = message
      case .ignored: return
      }
      reportEditingState()
    }

    /// Ends the save and shows the conflict banner, because the stored profile changed elsewhere.
    func applySaveConflict() {
      finishSave()
      showingConflict = true
      saveError = OJDLocalized.string(
        "ui.profiles.changedElsewhere"
      )
    }

    /// Ends the save and takes the stored profile as the saved state.
    ///
    /// When the library does not list the profile, the editor says the profile is saved but
    /// unavailable.
    func applySaveSuccess() {
      finishSave()
      saveError = nil
      guard case .available(let snapshot) = viewModel.remappingState,
        let latest = snapshot.profiles.first(where: { $0.id == profile.id })
      else {
        localError = OJDLocalized.string(
          "ui.profiles.savedButUnavailable"
        )
        saveError = localError
        return
      }
      expectedCurrent = latest
      draft = RuntimeProfileDraft(profile: latest)
    }

    /// Whether a save runs.
    var saveInFlight: Bool { saveState.isInFlight }

    /// The operation of the save in flight, or nil.
    var pendingUpdateOperation: RuntimeMutationOperation? { saveState.operation }

    /// The identifier of the save in flight, or nil.
    var pendingUpdateMutationID: UUID? { saveState.mutationID }
  }

  /// An action of the editor's menu.
  enum ProfileEditorMenuAction: Hashable {
    /// Opens the details sheet.
    case details
    /// Restores the default input.
    case restoreDefaultInput
    /// Clears all input.
    case clearInputs
    /// Removes every assignment.
    case removeAllAssignments
    /// Deactivates the active profile of the controller.
    case deactivateAll

    /// The title of the action in the menu.
    var title: String {
      switch self {
      case .details: return OJDLocalized.string("ui.profiles.details")
      case .restoreDefaultInput:
        return OJDLocalized.string(
          "ui.profiles.restoreDefaultInput"
        )
      case .clearInputs:
        return OJDLocalized.string("ui.profiles.clearInputs")
      case .removeAllAssignments:
        return OJDLocalized.string("ui.profiles.removeAllAssignments")
      case .deactivateAll:
        return OJDLocalized.string("ui.profiles.deactivateController")
      }
    }
  }

#endif
