import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct ProfileMutationTests {
  @Test func updatePreservesCompareAndSwapAndSurfacesConflict() async throws {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let gateway = GatewayStub(
      snapshotPayload: snapshot(profiles: [original]),
      updateShouldConflict: true
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))

    _ = await viewModel.updateRemappingProfile(
      proposed,
      expectedCurrent: original,
      request: request
    )

    #expect(await gateway.lastExpectedCurrent == original)
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .conflict(let profileID) = mutationState else {
      Issue.record("Expected a compare-and-swap conflict")
      return
    }
    #expect(profileID == original.id)
    #expect(
      await MainActor.run { viewModel.lastError }
        == "This profile changed elsewhere. Reload or keep editing."
    )
  }

  @Test func mutationSuccessIdentifiesUpdateButNotActivationAsDraftSave() async {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let updateRequest = RuntimeMutationRequest(operation: .update(profileID: original.id))

    _ = await viewModel.updateRemappingProfile(
      proposed,
      expectedCurrent: original,
      request: updateRequest
    )
    let saveState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = saveState else {
      Issue.record("Expected an identified profile update")
      return
    }
    #expect(profileID == original.id)

    _ = await viewModel.activateRemappingProfile(
      id: original.id,
      request: RuntimeMutationRequest(operation: .activate(profileID: original.id))
    )
    let activationState = await MainActor.run { viewModel.mutationState }
    guard case .completed(.activate(let activatedID)) = activationState else {
      Issue.record("Expected activation to be separate from profile save")
      return
    }
    #expect(activatedID == original.id)
  }

  @Test func deleteCallsGatewayAndImmediatelyPublishesTheReturnedProfileList() async {
    let deleted = makeProfile(name: "Delete Me")
    let retained = makeProfile(name: "Keep Me")
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [deleted, retained]))
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let request = RuntimeMutationRequest(operation: .delete(profileID: deleted.id))

    _ = await viewModel.deleteRemappingProfile(id: deleted.id, request: request)

    #expect(await gateway.deleteCallCount == 1)
    #expect(await gateway.lastDeletedProfileID == deleted.id)
    let state = await MainActor.run { viewModel.remappingState }
    guard case .available(let updated) = state else {
      Issue.record("Expected deletion to publish an available remapping snapshot")
      return
    }
    #expect(updated.profiles == [retained])
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .completed(.delete(let profileID)) = mutationState else {
      Issue.record("Expected a completed delete mutation")
      return
    }
    #expect(profileID == deleted.id)
  }

  @Test func importOverExistingIdentifierPublishesReplacementProfile() async {
    let original = makeProfile(name: "Original")
    let replacement = makeProfile(id: original.id, name: "Imported")
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: original.id))

    _ = await viewModel.importRemappingProfile(replacement, request: request)

    let state = await MainActor.run { viewModel.remappingState }
    guard case .available(let updated) = state else {
      Issue.record("Expected import to publish an available remapping snapshot")
      return
    }
    #expect(updated.profiles == [replacement])
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .completed(.importProfile(let profileID)) = mutationState else {
      Issue.record("Expected a completed import mutation")
      return
    }
    #expect(profileID == original.id)
  }

  @Test func preflightValidationReturnsTheExactRequestWithoutStartingRuntime() async {
    let original = makeProfile(name: "Original")
    let invalid = makeProfile(id: original.id, name: "")
    let request = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [original]))
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    let result = await viewModel.updateRemappingProfile(
      invalid,
      expectedCurrent: original,
      request: request
    )

    guard case .failed(let resultID, let operation, _) = result else {
      Issue.record("Expected invalid profile validation to fail")
      return
    }
    #expect(resultID == request.id)
    #expect(operation == request.operation)
    #expect(await gateway.updateCallCount == 0)
    #expect(await MainActor.run { viewModel.activeMutationID == nil })
    #expect(await MainActor.run { viewModel.lastMutationID == request.id })
    #expect(await MainActor.run { viewModel.lastMutationOperation == request.operation })
  }

  @Test func createAndImportPreflightFailuresKeepTheirRequestIdentity() async {
    let invalid = makeProfile(name: "")
    let gateway = GatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let createRequest = RuntimeMutationRequest(operation: .create(profileID: invalid.id))

    let createResult = await viewModel.createRemappingProfile(invalid, request: createRequest)
    #expect(createResult.id == createRequest.id)
    #expect(createResult.operation == createRequest.operation)

    let importRequest = RuntimeMutationRequest(operation: .importProfile(profileID: invalid.id))
    let importResult = await viewModel.importRemappingProfile(invalid, request: importRequest)
    #expect(importResult.id == importRequest.id)
    #expect(importResult.operation == importRequest.operation)
  }

  @Test func failedDeleteReturnsTheExactRequestAndLeavesRuntimeIdle() async {
    let profile = makeProfile()
    let request = RuntimeMutationRequest(operation: .delete(profileID: profile.id))
    let gateway = GatewayStub(
      snapshotPayload: snapshot(profiles: [profile]),
      deleteShouldFail: true
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    let result = await viewModel.deleteRemappingProfile(id: profile.id, request: request)

    guard case .failed(let resultID, let operation, _) = result else {
      Issue.record("Expected delete failure")
      return
    }
    #expect(resultID == request.id)
    #expect(operation == request.operation)
    #expect(await MainActor.run { viewModel.activeMutationID == nil })
    #expect(await MainActor.run { viewModel.lastMutationID == request.id })
  }

  @Test func overlappingMutationsRejectTheSecondRequestWhileSaving() async {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let ignored = makeProfile(id: original.id, name: "Ignored")
    let gateway = GatewayStub(
      snapshotPayload: snapshot(profiles: [original]),
      updateDelayNanoseconds: 100_000_000
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let firstRequest = RuntimeMutationRequest(operation: .update(profileID: original.id))
    let secondRequest = RuntimeMutationRequest(operation: .update(profileID: original.id))

    let first = Task { @MainActor in
      await viewModel.updateRemappingProfile(
        proposed,
        expectedCurrent: original,
        request: firstRequest
      )
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    let firstMutationID = await MainActor.run { viewModel.activeMutationID }
    #expect(
      await MainActor.run { viewModel.activeMutationOperation == .update(profileID: original.id) }
    )
    #expect(firstMutationID != nil)

    let second = Task { @MainActor in
      await viewModel.updateRemappingProfile(
        ignored,
        expectedCurrent: original,
        request: secondRequest
      )
    }
    let rejectedResult = await second.value
    guard case .rejected(let rejectedID, let rejectedOperation, _) = rejectedResult else {
      Issue.record("Expected the overlapping update to return a typed rejection")
      return
    }
    #expect(rejectedOperation == .update(profileID: original.id))

    let rejectedState = await MainActor.run { viewModel.mutationState }
    guard case .error(let rejectionMessage) = rejectedState else {
      Issue.record("Expected the overlapping update to be rejected explicitly")
      return
    }
    #expect(rejectionMessage == "Another profile action is already in progress.")
    #expect(
      await MainActor.run { viewModel.lastMutationOperation == .update(profileID: original.id) }
    )
    let rejectedMutationID = await MainActor.run { viewModel.lastMutationID }
    #expect(rejectedMutationID == rejectedID)
    #expect(rejectedID != firstMutationID)
    #expect(await MainActor.run { viewModel.activeMutationID == firstMutationID })

    let firstResult = await first.value
    guard case .succeeded(let completedID, let completedOperation) = firstResult else {
      Issue.record("Expected the first update to complete successfully")
      return
    }
    #expect(completedID == firstMutationID)
    #expect(completedOperation == .update(profileID: original.id))

    #expect(await gateway.updateCallCount == 1)
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = mutationState else {
      Issue.record("Expected only the first update to complete")
      return
    }
    #expect(profileID == original.id)
  }
}
