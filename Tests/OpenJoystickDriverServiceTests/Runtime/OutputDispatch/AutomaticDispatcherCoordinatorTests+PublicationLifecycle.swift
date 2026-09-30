import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension AutomaticDispatcherCoordinatorTests {

  var description: ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "probe",
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func installationUsesSuppressionChangedDuringSuspension() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()

    let backend = InstallationBackend(stage: .suppression, gate: gate)
    async let pending = coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    await coordinator.synchronizeSuppression { true }
    await gate.release()

    let lease = await pending
    #expect(lease == nil)
    await coordinator.close()
    #expect(backend.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))


  func suppressionRetiresOnlyPublicationAndRecreatesForTheCurrentSession() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let first = InstallationBackend(stage: .none, gate: InstallationGate())
    let second = InstallationBackend(stage: .none, gate: InstallationGate())
    let builds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in builds.next() == 0 ? first : second
    }

    let initial = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    try #require(initial != nil)
    await initial?.release()

    await coordinator.synchronizeSuppression { true }

    #expect(first.counts().closes == 1)
    #expect(await coordinator.installedTargets()[identifier] == nil)

    await coordinator.synchronizeSuppression { false }
    #expect(second.counts().activations == 1)
    #expect(await coordinator.installedTargets()[identifier] == .generic)
    await coordinator.close()
    #expect(second.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func suppressionCancelsPendingCreationBeforeItCanInstall() async {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: .activation, gate: gate)
    async let pending = coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    await coordinator.synchronizeSuppression { true }
    await gate.waitForCancellation()
    await gate.release()

    #expect(await pending == nil)
    #expect(backend.counts().activations == 1)
    #expect(backend.counts().closes == 1)
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func recoveryRetriesCreationFailureWithoutChangingMode() async throws {
    let coordinator = AutomaticDispatcherCoordinator(recoveryDelayNanoseconds: 1)
    let original = InstallationBackend(stage: .none, gate: InstallationGate())
    let failed = InstallationBackend(stage: .none, gate: InstallationGate(), failsActivation: true)
    let recovered = InstallationBackend(stage: .none, gate: InstallationGate())
    let builds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in
      switch builds.next() {
      case 0: original
      case 1: failed
      default: recovered
      }
    }
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    try #require(lease != nil)
    await lease?.release()
    await coordinator.recoverPublication(
      for: identifier,
      failure: UserSpaceOutputDispatcher.CreationError.createFailed
    )

    for _ in 0..<100 where recovered.counts().activations == 0 {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(failed.counts() == (1, 1))
    #expect(recovered.counts().activations == 1)
    await coordinator.close()
    #expect(recovered.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func sameIdentifierReconnectCreatesANewPublicationWithoutChangingMode() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let first = InstallationBackend(stage: .none, gate: InstallationGate())
    let second = InstallationBackend(stage: .none, gate: InstallationGate())
    let builds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in builds.next() == 0 ? first : second
    }

    let initial = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    try #require(initial != nil)
    await initial?.release()
    await coordinator.stop(identifier)
    #expect(first.counts().closes == 1)

    try await coordinator.activateOne(
      identifier: identifier,
      descriptions: [description],
      isEligible: { _, _ in true },
      profileProvider: { _ in .generic },
      factory: factory
    )
    #expect(second.counts().activations == 1)
    await coordinator.close()
    #expect(second.counts().closes == 1)
  }

  @Test(
    .timeLimit(.minutes(1)),
    arguments: [InstallationBackend.Stage.activation, .suppression],
    [false, true]
  )
  private func stopDrainsSuspendedInstallation(
    stage: InstallationBackend.Stage,
    shutdown: Bool
  ) async {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: stage, gate: gate)
    async let lease = coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    async let stopped: Void = shutdown ? coordinator.close() : coordinator.stop(identifier)
    await gate.waitForCancellation()
    #expect(backend.counts().closes == 0)
    await gate.release()
    await stopped
    #expect(await lease == nil)
    #expect(backend.counts().closes == 1)
    let stale = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    #expect(stale == nil)
    await coordinator.close()
    #expect(backend.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func closeDuringRetirementNeverActivatesReplacement() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let original = InstallationBackend(stage: .retirement, gate: gate)
    let replacement = InstallationBackend(stage: .activation, gate: InstallationGate())
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in original }
    )
    try #require(lease != nil)
    await lease?.release()
    async let replaced = coordinator.leaseForDispatch(
      controller: identifier,
      profile: .xboxOneSBluetooth,
      isEligible: { _, _ in true },
      factory: { _ in replacement }
    )
    await gate.waitForEntry()
    async let closed: Void = coordinator.close()
    await gate.waitForCancellation()
    #expect(original.counts().closes == 0)
    #expect(replacement.counts().activations == 0)
    await gate.release()
    await closed
    #expect(await replaced == nil)
    #expect(original.counts().closes == 1)
    #expect(replacement.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func stopThatTimesOutStillClearsRetirementOnceTheNativeCloseFinishes() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let original = InstallationBackend(stage: .retirement, gate: gate)
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in original }
    )
    try #require(lease != nil)

    // The held lease makes retirement time out, which leaves the slot recorded as retiring.
    await coordinator.stop(identifier)
    #expect(await coordinator.entries[identifier]?.retiring != nil)

    await gate.release()
    while await coordinator.entries[identifier]?.retiring != nil { await Task.yield() }
    #expect(original.counts().closes == 1)
    await lease?.release()
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func retargetBlockedByAnUnclosedSlotPublishesUntilTheCloseFinishes() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let original = InstallationBackend(stage: .retirement, gate: gate)
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: { _ in original }
    )
    try #require(lease != nil)
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in
      InstallationBackend(stage: .none, gate: InstallationGate())
    }

    // The held lease and blocked native close make the original slot's retirement time out.
    try await coordinator.retarget(
      identifier,
      target: .xboxOneSBluetooth,
      isEligible: { _, _ in true },
      factory: factory
    )
    #expect(await coordinator.entries[identifier]?.retiring != nil)

    // A replacement never publishes beside a device still closing, so this retarget fails...
    await #expect(throws: CancellationError.self) {
      try await coordinator.retarget(
        identifier,
        target: .generic,
        isEligible: { _, _ in true },
        factory: factory
      )
    }
    // ...while the live replacement keeps publishing.
    #expect(await coordinator.installedTargets() == [identifier: .xboxOneSBluetooth])

    // Once the native close finishes, the slot is cleared and the next retarget publishes.
    await gate.release()
    while await coordinator.entries[identifier]?.retiring != nil { await Task.yield() }
    #expect(original.counts().closes == 1)
    try await coordinator.retarget(
      identifier,
      target: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    #expect(await coordinator.installedTargets() == [identifier: .generic])
    await lease?.release()
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func eligibilityCannotResurrectStoppedController() async {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: .activation, gate: InstallationGate())
    async let lease = coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in
        await gate.suspend()
        return true
      },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    await coordinator.stop(identifier)
    await gate.release()
    #expect(await lease == nil)
    #expect(backend.counts().activations == 0)
    await coordinator.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func failedProfileReplacementActivationRestoresPriorTarget() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let original = InstallationBackend(stage: .none, gate: InstallationGate())
    let failed = InstallationBackend(stage: .none, gate: InstallationGate(), failsActivation: true)
    let restored = InstallationBackend(stage: .none, gate: InstallationGate())
    let canonicalBuilds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { profile in
      if profile == .xboxOneSBluetooth { return failed }
      return canonicalBuilds.next() == 0 ? original : restored
    }

    let first = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    try #require(first != nil)
    await first?.release()
    let replacement = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .xboxOneSBluetooth,
      isEligible: { _, _ in true },
      factory: factory
    )

    #expect(replacement == nil)
    #expect(original.counts().closes == 1)
    #expect(failed.counts() == (1, 1))
    #expect(restored.counts() == (1, 0))
    let retained = await coordinator.leaseForDispatch(
      controller: identifier,
      profile: .generic,
      isEligible: { _, _ in true },
      factory: factory
    )
    #expect(retained != nil)
    await retained?.release()
    await coordinator.close()
    #expect(restored.counts().closes == 1)
  }
  @Test(.timeLimit(.minutes(1)))
  func unavailableProfileSelectionNeverBuildsABackend() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let builds = AutomaticBuildCounter()
    let factory: AutomaticDispatcherCoordinator.Factory = { _ in
      _ = builds.next()
      return InstallationBackend(stage: .none, gate: InstallationGate())
    }

    try await coordinator.activateOne(
      identifier: identifier,
      descriptions: [description],
      isEligible: { _, _ in true },
      profileProvider: { _ in nil },
      factory: factory
    )
    try await coordinator.activate(
      identifiers: [identifier],
      descriptions: [description],
      isEligible: { _, _ in true },
      profileProvider: { _ in nil },
      factory: factory
    )

    #expect(builds.next() == 0)
    #expect(await coordinator.installedTargets().isEmpty)
    await coordinator.close()
  }
}
