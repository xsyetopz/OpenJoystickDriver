#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {
    func addBinding(source: RemappingSource, destination: RemappingDestination) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.addingBinding(source: source, destination: destination)
        activeSheet = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    func removeBinding(_ id: UUID) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.removingBinding(id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    func updateAxisTuning(_ tuning: RemappingAxisTuning, for id: UUID) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.settingAxisTuning(tuning, for: id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    func updateMetadata(_ profile: RemappingProfile) {
      guard !isEditingDisabled else { return }
      draft = RuntimeProfileDraft(profile: profile)
      localError = nil
      saveError = nil
      reportEditingState()
    }

    var activationLabel: String {
      if profile.joyConPair != nil {
        return OJDLocalized.string("profiles.joyConSessionState")
      }
      return OJDLocalized.string(
        isActive ? "profiles.active" : "profiles.notActive"
      )
    }

    func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("profiles.assignments", count: count)
    }

    var menuActions: [ProfileEditorMenuAction] {
      var actions: [ProfileEditorMenuAction] = [.duplicate, .export]
      if draft.profile.suppressesAllControllerInput { actions.append(.restoreDefaultInput) }
      actions.append(.clearInputs)
      if isActive, profile.joyConPair == nil { actions.append(.deactivateAll) }
      return actions
    }

    func performMenuAction(_ action: ProfileEditorMenuAction) {
      switch action {
      case .duplicate: duplicateProfile()
      case .export:
        do { onExport(try draft.validatedProfile()) } catch {
          localError = RuntimePresentation.userFacingError(error)
        }
      case .details: activeSheet = .metadata
      case .restoreDefaultInput: restoreDefaultInput()
      case .clearInputs: confirmation = .clearInputs
      case .deactivateAll: deactivateAllProfiles()
      }
    }

    func restoreDefaultInput() {
      applyDraftChange { RuntimeProfileDraft(profile: draft.profile.restoringDefaultInput()) }
    }

    func clearInputs() {
      applyDraftChange { RuntimeProfileDraft(profile: draft.profile.clearingAllInput()) }
    }

    func requestActivation() {
      if profile.producesNoOutput {
        confirmation = .activateEmpty
      } else {
        activateProfile()
      }
    }

    func activateProfile() {
      guard !isMutationActive else { return }
      let request = RuntimeMutationRequest(operation: .activate(profileID: profile.id))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await library.activateRemappingProfile(id: profile.id, request: request)
        onMutationResult(result)
      }
    }

    func deactivateProfile() {
      guard !isMutationActive else { return }
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

    func deactivateAllProfiles() {
      guard !isMutationActive else { return }
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

    func removeChord(_ id: UUID) { applyDraftChange { try draft.removingChord(id) } }

    func addSequence(
      sources: [RemappingSource],
      windowMs: Double,
      destination: RemappingDestination
    ) {
      applyDraftChange {
        try draft.addingSequence(sources: sources, windowMs: windowMs, destination: destination)
      }
    }

    func removeSequence(_ id: UUID) { applyDraftChange { try draft.removingSequence(id) } }

    func addLayer(name: String, activator: RemappingSource, mode: RemappingLayerActivation) {
      applyDraftChange {
        try draft.addingLayer(name: name, activator: activator, activationMode: mode)
      }
    }

    func removeLayer(_ id: UUID) { applyDraftChange { try draft.removingLayer(id) } }

    func setLayerBinding(layerID: UUID, source: RemappingSource, destination: RemappingDestination)
    {
      applyDraftChange {
        try draft.settingLayerBinding(layerID: layerID, source: source, destination: destination)
      }
    }

    func removeLayerBinding(layerID: UUID, bindingID: UUID) {
      applyDraftChange { try draft.removingLayerBinding(layerID: layerID, bindingID: bindingID) }
    }

    func updateLayerAxisTuning(_ tuning: RemappingAxisTuning, layerID: UUID, bindingID: UUID) {
      applyDraftChange {
        try draft.settingLayerBindingAxisTuning(
          layerID: layerID,
          bindingID: bindingID,
          axisTuning: tuning
        )
      }
    }

    func applyDraftChange(_ change: () throws -> RuntimeProfileDraft) {
      guard !isEditingDisabled else { return }
      do {
        draft = try change()
        localError = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    func save() {
      guard draft.profile != expectedCurrent, !saveInFlight, !isEditingDisabled else { return }
      let operation = RuntimeMutationOperation.update(profileID: profile.id)
      let request = RuntimeMutationRequest(operation: operation)
      guard saveState.begin(request) else { return }
      saveError = nil
      localError = nil
      guard onMutationStarted(request) else {
        finishSave()
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

    func duplicateProfile() {
      guard !isEditingDisabled else { return }
      let source = draft.profile
      let duplicate = duplicatedProfile(source)
      let request = RuntimeMutationRequest(operation: .create(profileID: duplicate.id))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await library.createRemappingProfile(duplicate, request: request)
        onMutationResult(result)
      }
    }

    func reportEditingState() {
      onEditingStateChanged(saveInFlight || draft.profile != expectedCurrent)
    }

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

    func finishSave() { saveState.cancel() }

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

    func applySaveConflict() {
      finishSave()
      showingConflict = true
      saveError = OJDLocalized.string(
        "profiles.changedElsewhere"
      )
    }

    func applySaveSuccess() {
      finishSave()
      saveError = nil
      guard case .available(let snapshot) = viewModel.remappingState,
        let latest = snapshot.profiles.first(where: { $0.id == profile.id })
      else {
        localError = OJDLocalized.string(
          "profiles.savedButUnavailable"
        )
        saveError = localError
        return
      }
      expectedCurrent = latest
      draft = RuntimeProfileDraft(profile: latest)
    }

    var saveInFlight: Bool { saveState.isInFlight }

    var pendingUpdateOperation: RuntimeMutationOperation? { saveState.operation }

    var pendingUpdateMutationID: UUID? { saveState.mutationID }
  }

  enum ProfileEditorMenuAction: Hashable {
    case duplicate
    case export
    case details
    case restoreDefaultInput
    case clearInputs
    case deactivateAll

    var title: String {
      switch self {
      case .duplicate: return OJDLocalized.string("common.duplicate")
      case .export: return OJDLocalized.string("profiles.export")
      case .details: return OJDLocalized.string("profiles.details")
      case .restoreDefaultInput:
        return OJDLocalized.string(
          "profiles.restoreDefaultInput"
        )
      case .clearInputs:
        return OJDLocalized.string("profiles.clearInputs")
      case .deactivateAll:
        return OJDLocalized.string("profiles.deactivateController")
      }
    }
  }

#endif
