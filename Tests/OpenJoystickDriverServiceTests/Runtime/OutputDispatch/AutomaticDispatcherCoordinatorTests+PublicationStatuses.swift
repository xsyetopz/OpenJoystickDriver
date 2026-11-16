import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension AutomaticDispatcherCoordinatorTests {
  @Test(.timeLimit(.minutes(1)))
  func publicationStatusesReportPublishedThenFailedWithFailureText() async throws {
    // A recovery delay this long keeps the failed state until the coordinator closes.
    let coordinator = AutomaticDispatcherCoordinator(recoveryDelayNanoseconds: 3_600_000_000_000)
    let backend = InstallationBackend(stage: .none, gate: InstallationGate())
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    try #require(lease != nil)
    await lease?.release()

    let published = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(published.state == .published)
    #expect(published.target == .generic)
    #expect(published.reason == nil && published.failure == nil)

    await coordinator.recoverPublication(
      for: identifier,
      failure: UserSpaceOutputDispatcher.CreationError.createFailed
    )

    let failed = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(failed.state == .failed)
    #expect(
      failed.failure == String(describing: UserSpaceOutputDispatcher.CreationError.createFailed)
    )
    #expect(failed.reason == nil)
    #expect(failed.target == .generic)
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func controllerHeldByAnotherClientPublishesNothingUntilItIsReleased() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let backend = InstallationBackend(stage: .none, gate: InstallationGate())
    let lease: () async -> AutomaticBackendLease? = {
      await coordinator.leaseForDispatch(
        controller: self.identifier,
        profile: .generic,
        isEligible: { _, _ in true },
        factory: { _ in backend }
      )
    }
    await lease()?.release()
    #expect(await coordinator.publicationStatuses()[identifier]?.state == .published)

    await coordinator.setHeldByAnotherClient(true, for: identifier)
    #expect(backend.counts().closes == 1)
    #expect(await coordinator.installedBackend(for: identifier) == nil)
    #expect(await lease() == nil)
    let held = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(held.state == .notPublished && held.reason == .heldByAnotherClient)
    #expect(held.target == .generic)

    await coordinator.setHeldByAnotherClient(false, for: identifier)
    let released = try #require(await lease())
    await released.release()
    #expect(await coordinator.publicationStatuses()[identifier]?.state == .published)
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func controllerHeldBeforeItsFirstPublicationReportsHeldReason() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let backend = InstallationBackend(stage: .none, gate: InstallationGate())
    await coordinator.setHeldByAnotherClient(true, for: identifier)
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    #expect(lease == nil)
    #expect(backend.counts().activations == 0)
    let held = try #require(await coordinator.publicationStatuses()[identifier])
    #expect(held.state == .notPublished && held.reason == .heldByAnotherClient)
    await coordinator.close()
  }
}
