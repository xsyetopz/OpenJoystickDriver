import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

extension RuntimeProfileDraftTests {
  @Test
  func confirmedImportSuccessKeepsEditorCleanAndRefreshable() {
    let imported = makeProfile(name: "Imported")
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: imported.id))
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    #expect(state.request(.importProfile(imported)) == .confirmDiscard)
    #expect(state.discardPendingAction() == .importProfile(imported))
    state.beginMutation(request)
    #expect(state.request(.select(UUID())) == .blocked)

    let shouldRefreshEditor = state.finishMutation(request)
    #expect(shouldRefreshEditor)
    #expect(!state.isDirty)
    #expect(state.request(.select(UUID())) != .confirmDiscard)
  }

  @Test
  func dirtyDeleteBlocksSelectionAndFailureRestoresDraftProtection() {
    let profile = makeProfile()

    let otherProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .delete(profileID: profile.id))
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    state.beginMutation(request, restoresDirtyOnFailure: true)
    state.setDirty(false)

    #expect(state.request(.select(otherProfileID)) == .blocked)

    #expect(state.pendingAction == nil)
    _ = state.finishMutation(request, succeeded: false)

    #expect(state.isDirty)
    #expect(state.request(.select(otherProfileID)) == .confirmDiscard)
    #expect(state.pendingAction == .select(otherProfileID))
  }

  @Test
  func successfulDeleteReleasesOperationAndKeepsCleanEditorNavigable() {
    let profile = makeProfile()
    let request = RuntimeMutationRequest(operation: .delete(profileID: profile.id))
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    state.beginMutation(request, restoresDirtyOnFailure: true)
    state.setDirty(false)

    #expect(state.request(.importProfile(makeProfile(name: "Other"))) == .blocked)
    let shouldRefreshEditor = state.finishMutation(request)
    #expect(shouldRefreshEditor)
    #expect(!state.isEditingBlocked)
    #expect(!state.isDirty)
    #expect(state.request(.select(UUID())) != .confirmDiscard)
  }

  @Test
  func completedCreateSelectsCreatedProfileAfterOperationReleases() {
    let createdProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .create(profileID: createdProfileID))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    _ = state.finishMutation(request)
    #expect(
      ProfileEditorMutationCompletion.action(
        for: .create(profileID: createdProfileID),
        selectedProfileID: nil,
        shouldRefreshEditor: false
      ) == .select(createdProfileID)
    )
  }

  @Test
  func completedDuplicateSelectsDuplicateAfterOperationReleases() {
    let duplicateProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .create(profileID: duplicateProfileID))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    let shouldRefreshEditor = state.finishMutation(request)
    #expect(
      ProfileEditorMutationCompletion.action(
        for: .create(profileID: duplicateProfileID),
        selectedProfileID: UUID(),
        shouldRefreshEditor: shouldRefreshEditor
      ) == .select(duplicateProfileID)
    )
  }

  @Test
  func completedDifferentIDImportSelectsImportedProfileAfterOperationReleases() {
    let importedProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: importedProfileID))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    let shouldRefreshEditor = state.finishMutation(request)
    #expect(
      ProfileEditorMutationCompletion.action(
        for: .importProfile(profileID: importedProfileID),
        selectedProfileID: UUID(),
        shouldRefreshEditor: shouldRefreshEditor
      ) == .select(importedProfileID)
    )
  }

  @Test
  func mutationOwnershipRejectsDifferentAndDuplicateStarts() {
    let first = RuntimeMutationRequest(operation: .delete(profileID: UUID()))
    let second = RuntimeMutationRequest(operation: .importProfile(profileID: UUID()))
    var state = ProfileEditorTransitionState()

    #expect(state.beginMutation(first) == .acquired)
    #expect(state.beginMutation(first) == .alreadyOwned)
    #expect(state.beginMutation(second) == .rejected)
    #expect(state.activeMutationOperation == first.operation)
    #expect(state.isEditingBlocked)
  }

  @Test
  func mismatchedRuntimeCompletionCannotReleaseActiveMutation() {
    let operation = RuntimeMutationOperation.delete(profileID: UUID())
    let ownerID = UUID()
    let unrelatedID = UUID()
    let owner = RuntimeMutationRequest(operation: operation, id: ownerID)
    let unrelated = RuntimeMutationRequest(operation: operation, id: unrelatedID)
    var state = ProfileEditorTransitionState()
    _ = state.beginMutation(owner)
    let didBind = state.bindRuntimeMutation(owner)
    #expect(didBind)

    #expect(state.finishMutationIfOwned(unrelated, succeeded: false) == .ignored)
    #expect(state.isEditingBlocked)
    #expect(state.finishMutationIfOwned(owner) == .released(shouldRefreshEditor: true))
    #expect(!state.isEditingBlocked)
  }

  @Test
  func matchingPreflightFailureReleasesExactOwnerAndKeepsDraftDirty() {
    let request = RuntimeMutationRequest(operation: .update(profileID: UUID()))
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    #expect(state.beginMutation(request) == .acquired)
    #expect(
      state.finishMutationIfOwned(
        RuntimeMutationRequest(operation: request.operation),
        succeeded: false
      ) == .ignored
    )
    #expect(state.isEditingBlocked)

    let result = RuntimeMutationResult.failed(
      id: request.id,
      operation: request.operation,
      message: "validation"
    )
    #expect(
      state.finishMutationIfOwned(result.request, succeeded: false)
        == .released(shouldRefreshEditor: false)
    )
    #expect(state.isDirty)
    #expect(!state.isEditingBlocked)
  }

  @Test
  func activeOwnerIsReconciledBeforeProcessingOverlappingError() {
    let operation = RuntimeMutationOperation.update(profileID: UUID())
    let ownerID = UUID()
    let rejectedID = UUID()
    let owner = RuntimeMutationRequest(operation: operation, id: ownerID)
    let rejected = RuntimeMutationRequest(operation: operation, id: rejectedID)
    var state = ProfileEditorTransitionState()

    #expect(state.reconcileRuntimeMutation(owner).isAccepted)
    #expect(state.finishMutationIfOwned(rejected, succeeded: false) == .ignored)
    #expect(state.activeMutationOperation == operation)
    #expect(state.activeRuntimeMutationID == ownerID)
    #expect(state.isEditingBlocked)
  }

  @Test
  func duplicateSaveStartDoesNotAcquireSecondOwner() {
    let operation = RuntimeMutationOperation.update(profileID: UUID())
    let first = RuntimeMutationRequest(operation: operation)
    let second = RuntimeMutationRequest(operation: operation)
    var state = ProfileEditorSaveState()

    let didBegin = state.begin(first)
    let didBeginDuplicate = state.begin(second)
    #expect(didBegin)
    #expect(!didBeginDuplicate)
    #expect(state.isInFlight)
    #expect(state.mutationID == first.id)
  }

  @Test
  func losingSameOperationSaveResolvesByItsOwnRejectedMutationID() {
    let operation = RuntimeMutationOperation.update(profileID: UUID())
    let request = RuntimeMutationRequest(operation: operation)
    let winner = RuntimeMutationRequest(operation: operation)
    var state = ProfileEditorSaveState()
    let didBegin = state.begin(request)
    #expect(didBegin)

    #expect(state.resolve(.succeeded(id: winner.id, operation: operation)) == .ignored)
    #expect(state.isInFlight)

    let resolution = state.resolve(
      .rejected(id: request.id, operation: operation, message: "rejected")
    )
    guard case .failed = resolution else {
      Issue.record("Expected the losing save to resolve as a failure")
      return
    }
    #expect(!state.isInFlight)
  }

  @Test
  func matchingSaveCompletionResolvesSuccessfully() {
    let operation = RuntimeMutationOperation.update(profileID: UUID())
    let request = RuntimeMutationRequest(operation: operation)
    var state = ProfileEditorSaveState()
    let didBegin = state.begin(request)
    #expect(didBegin)

    #expect(state.resolve(.succeeded(id: request.id, operation: operation)) == .succeeded)
    #expect(!state.isInFlight)
  }

  func makeProfile(id: UUID = UUID(), name: String = "Test Profile") -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ]
    )
  }

}
