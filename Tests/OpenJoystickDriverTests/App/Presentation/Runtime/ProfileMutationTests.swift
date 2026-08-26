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

    await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)

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

    await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)
    let saveState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = saveState else {
      Issue.record("Expected an identified profile update")
      return
    }
    #expect(profileID == original.id)

    await viewModel.activateRemappingProfile(id: original.id)
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

    await viewModel.deleteRemappingProfile(id: deleted.id)

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

    await viewModel.importRemappingProfile(replacement)

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

  @Test func overlappingMutationsRejectTheSecondRequestWhileSaving() async {
    let original = makeProfile(name: "Original")
    let proposed = makeProfile(id: original.id, name: "Proposed")
    let ignored = makeProfile(id: original.id, name: "Ignored")
    let gateway = GatewayStub(
      snapshotPayload: snapshot(profiles: [original]),
      updateDelayNanoseconds: 100_000_000
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    let first = Task { @MainActor in
      await viewModel.updateRemappingProfile(proposed, expectedCurrent: original)
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
    #expect(
      await MainActor.run { viewModel.activeMutationOperation == .update(profileID: original.id) }
    )

    let second = Task { @MainActor in
      await viewModel.updateRemappingProfile(ignored, expectedCurrent: original)
    }
    await second.value

    let rejectedState = await MainActor.run { viewModel.mutationState }
    guard case .error(let rejectionMessage) = rejectedState else {
      Issue.record("Expected the overlapping update to be rejected explicitly")
      return
    }
    #expect(rejectionMessage == "Another profile action is already in progress.")
    #expect(
      await MainActor.run { viewModel.lastMutationOperation == .update(profileID: original.id) }
    )

    await first.value

    #expect(await gateway.updateCallCount == 1)
    let mutationState = await MainActor.run { viewModel.mutationState }
    guard case .succeeded(let profileID) = mutationState else {
      Issue.record("Expected only the first update to complete")
      return
    }
    #expect(profileID == original.id)
  }
}
