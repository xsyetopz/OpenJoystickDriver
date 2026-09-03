import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

private actor CompatibilityTransitionGate {
  private var opened = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    opened = true
    let pending = waiters
    waiters.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

private final class CompatibilityTransitionProbe: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, @unchecked Sendable
{
  struct ActivationFailure: Error, Sendable {}

  let identity: CompatibilityIdentity
  let activationGate: CompatibilityTransitionGate?
  let closeGate: CompatibilityTransitionGate?
  let failsActivation: Bool
  private let lock = NSLock()
  private var closeCount = 0
  private var activations: [[DeviceIdentifier]] = []

  init(
    identity: CompatibilityIdentity,
    activationGate: CompatibilityTransitionGate? = nil,
    closeGate: CompatibilityTransitionGate? = nil,
    failsActivation: Bool = false
  ) {
    self.identity = identity
    self.activationGate = activationGate
    self.closeGate = closeGate
    self.failsActivation = failsActivation
  }

  var closeCountValue: Int { lock.withLock { closeCount } }
  var activationValues: [[DeviceIdentifier]] { lock.withLock { activations } }
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    lock.withLock { activations.append(identifiers) }
    await activationGate?.wait()
    if failsActivation { throw ActivationFailure() }
  }

  func activate(controller identifier: DeviceIdentifier) async throws {
    try await activate(for: [identifier])
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {}
  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
  func close() async {
    await closeGate?.wait()
    lock.withLock { closeCount += 1 }
  }
}

private final class CompatibilityTransitionFactory: @unchecked Sendable {
  struct BuildFailure: Error, Sendable {}

  private let lock = NSLock()
  private var probes: [CompatibilityTransitionProbe] = []
  var buildFailures: Set<CompatibilityIdentity> = []
  var activationFailures: Set<CompatibilityIdentity> = []
  var firstActivationGate: CompatibilityTransitionGate?
  var closeGates: [CompatibilityIdentity: CompatibilityTransitionGate] = [:]

  func make(_ identity: CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching
  {
    if buildFailures.contains(identity) { throw BuildFailure() }
    return lock.withLock { () -> CompatibilityTransitionProbe in
      let probe = CompatibilityTransitionProbe(
        identity: identity,
        activationGate: probes.isEmpty ? firstActivationGate : nil,
        closeGate: closeGates[identity],
        failsActivation: activationFailures.contains(identity)
      )
      probes.append(probe)
      return probe
    }
  }

  func values() -> [CompatibilityTransitionProbe] { lock.withLock { probes } }

  func waitForCount(_ count: Int) async {
    while lock.withLock({ probes.count }) < count { await Task.yield() }
  }
}

private final class IdentifierSnapshotBox: @unchecked Sendable {
  private let lock = NSLock()
  private var snapshots: [[DeviceIdentifier]]

  init(_ snapshots: [[DeviceIdentifier]]) { self.snapshots = snapshots }

  func next() -> [DeviceIdentifier] {
    lock.withLock {
      guard snapshots.count > 1 else { return snapshots.first ?? [] }
      return snapshots.removeFirst()
    }
  }
}

@Suite(.serialized) struct CompatibilityTransitionTests {
  private func transitionServer(
    factory: CompatibilityTransitionFactory,
    identifiers: [DeviceIdentifier],
    timeouts: CompatibilityTransitionTimeouts = .standard,
    clock: CompatibilityTransitionClock = .system,
    identifierProvider: (@Sendable () async -> [DeviceIdentifier])? = nil
  ) -> (ApplicationServiceServer, CompatibilityTransitionProbe) {
    let compatibilityDispatcher = CompatibilityOutputDispatcher()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess)
    )
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: remappingEngine,
      compatibility: compatibilityDispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: remappingRouter),
      permissionManager: PermissionManager(),
      dispatcher: compatibilityDispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess,
      userSpaceDispatcherBuilder: { try factory.make($0) },
      connectedIdentifierProvider: identifierProvider ?? { identifiers },
      compatibilityTransitionTimeouts: timeouts,
      compatibilityTransitionClock: clock,
      initializeCompatibilityBackend: false
    )
    let old = CompatibilityTransitionProbe(identity: .genericHID)
    server.userSpaceLock.withLock {
      server.compatibilityIdentity = .genericHID
      server.userSpaceDispatcher = old
      server.userSpaceEnabled = true
      server.userSpaceStatus = old.status
      server.compatibilityLiveIdentity = .genericHID
      compatibilityDispatcher.setBackend(old)
    }
    return (server, old)
  }

  private func requestIdentity(
    _ server: ApplicationServiceServer,
    _ identity: CompatibilityIdentity
  ) async -> Bool {
    await withCheckedContinuation { continuation in
      server.setCompatibilityIdentity(identity.rawValue) { continuation.resume(returning: $0) }
    }
  }

  @Test func stageFailurePreservesLiveBackendAndPersistence() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let prior = defaults.object(forKey: key)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    let factory = CompatibilityTransitionFactory()
    factory.buildFailures = [.appleGameController]
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(old.closeCountValue == 0)
    #expect(server.userSpaceDispatcher === old)
    #expect(server.userSpaceEnabled)
    #expect(server.compatibilityIdentity == .genericHID)
    #expect(defaults.string(forKey: key) == CompatibilityIdentity.genericHID.rawValue)
  }

  @Test func successfulTransitionActivatesBeforeCommitAndClosesOldOnce() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let prior = defaults.object(forKey: key)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(factory: factory, identifiers: [identifier])

    #expect(await requestIdentity(server, .appleGameController))
    let candidate = factory.values().first
    #expect(candidate?.activationValues == [[identifier]])
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceDispatcher === candidate)
    #expect(server.compatibilityIdentity == .appleGameController)
    #expect(defaults.string(forKey: key) == CompatibilityIdentity.appleGameController.rawValue)
  }

  @Test func candidateFailureRollsBackOneCoherentPriorBackend() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let prior = defaults.object(forKey: key)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    let factory = CompatibilityTransitionFactory()
    factory.activationFailures = [.appleGameController]
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    let probes = factory.values()
    #expect(probes.count == 2)
    #expect(probes[0].closeCountValue == 1)
    #expect(probes[1].closeCountValue == 0)
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceDispatcher === probes[1])
    #expect(server.userSpaceEnabled)
    #expect(server.compatibilityIdentity == .genericHID)
    #expect(defaults.string(forKey: key) == CompatibilityIdentity.genericHID.rawValue)
  }

  @Test func rollbackFailureLeavesOutputUnavailableWithoutAStaleBackend() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let retryKey = ApplicationServiceServer.compatibilityRetrySnapshotDefaultsKey
    let prior = defaults.object(forKey: key)
    let priorRetry = defaults.object(forKey: retryKey)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
      if let priorRetry {
        defaults.set(priorRetry, forKey: retryKey)
      } else {
        defaults.removeObject(forKey: retryKey)
      }
    }

    let factory = CompatibilityTransitionFactory()
    factory.activationFailures = [.appleGameController, .genericHID]
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(factory.values().allSatisfy { $0.closeCountValue == 1 })
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.currentUserSpaceStatus().hasPrefix("error:"))
    #expect(server.compatibilityIdentity == .appleGameController)
    #expect(defaults.string(forKey: key) == CompatibilityIdentity.appleGameController.rawValue)
    #expect(
      server.compatibilityRetrySnapshot
        == CompatibilityRetrySnapshot(
          requestedIdentity: .appleGameController,
          priorProfileIdentity: .genericHID,
          phase: .rollbackActivation
        )
    )
  }

  @Test func persistedRetrySnapshotLoadsAfterRestartAndSameIntentCanRetry() async {
    let defaults = UserDefaults.standard
    let identityKey = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let retryKey = ApplicationServiceServer.compatibilityRetrySnapshotDefaultsKey
    let priorIdentity = defaults.object(forKey: identityKey)
    let priorRetry = defaults.object(forKey: retryKey)
    defer {
      if let priorIdentity {
        defaults.set(priorIdentity, forKey: identityKey)
      } else {
        defaults.removeObject(forKey: identityKey)
      }
      if let priorRetry {
        defaults.set(priorRetry, forKey: retryKey)
      } else {
        defaults.removeObject(forKey: retryKey)
      }
    }

    let snapshot = CompatibilityRetrySnapshot(
      requestedIdentity: .appleGameController,
      priorProfileIdentity: .genericHID,
      phase: .rollbackActivation
    )
    defaults.set(CompatibilityIdentity.appleGameController.rawValue, forKey: identityKey)
    ApplicationServiceServer.persistCompatibilityRetrySnapshot(snapshot, defaults: defaults)

    let factory = CompatibilityTransitionFactory()
    let (server, placeholder) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    #expect(server.compatibilityRetrySnapshot == snapshot)
    server.userSpaceLock.withLock {
      server.dispatcher.setBackend(nil)
      server.userSpaceDispatcher = nil
      server.userSpaceCloseSlot = nil
      server.userSpaceEnabled = false
      server.compatibilityIdentity = .appleGameController
      server.persistedCompatibilityIdentity = .appleGameController
      server.compatibilityLiveIdentity = nil
    }
    await placeholder.close()

    #expect(await requestIdentity(server, .appleGameController))
    #expect(server.compatibilityIdentity == .appleGameController)
    #expect(server.compatibilityLiveIdentity == .appleGameController)
    #expect(server.compatibilityRetrySnapshot == nil)
    #expect(defaults.object(forKey: retryKey) == nil)
  }

  @Test func automaticTransitionRequestsAreGenerationScopedAndCoalesced() async {
    let defaults = UserDefaults.standard
    let identityKey = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let priorIdentity = defaults.object(forKey: identityKey)
    defer {
      if let priorIdentity {
        defaults.set(priorIdentity, forKey: identityKey)
      } else {
        defaults.removeObject(forKey: identityKey)
      }
    }
    let factory = CompatibilityTransitionFactory()
    let (server, _) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let generation = UUID()
    server.userSpaceLock.withLock {
      server.compatibilityIdentity = .automatic
      server.userSpaceAutomaticGeneration = generation
    }

    server.requestAutomaticCompatibilityTransition(generation: generation)
    server.requestAutomaticCompatibilityTransition(generation: generation)
    await factory.waitForCount(1)
    while server.compatibilityLiveIdentity != .automatic { await Task.yield() }

    #expect(factory.values().count == 1)
    server.requestAutomaticCompatibilityTransition(generation: generation)
    await Task.yield()
    #expect(factory.values().count == 1)
  }

  @Test func zeroControllerActivationUsesTheRemainingZeroDeviceBudget() async {
    let activationGate = CompatibilityTransitionGate()
    let factory = CompatibilityTransitionFactory()
    factory.firstActivationGate = activationGate
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [],
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 100_000_000,
        perControllerNanoseconds: 100_000_000,
        totalNanoseconds: 100_000_000,
        zeroControllerActivationNanoseconds: 100_000_000,
        feedbackNanoseconds: 100_000_000,
        candidateCloseNanoseconds: 100_000_000,
        rollbackStageNanoseconds: 100_000_000,
        rollbackActivationTotalNanoseconds: 100_000_000,
        zeroDeviceNanoseconds: 5_000_000
      )
    )

    let started = DispatchTime.now().uptimeNanoseconds
    #expect(await requestIdentity(server, .appleGameController) == false)
    let elapsed = DispatchTime.now().uptimeNanoseconds - started
    #expect(old.closeCountValue == 1)
    #expect(elapsed < 50_000_000)
    #expect(factory.values().count == 1)
    #expect(factory.values().first?.activationValues == [[]])
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.compatibilityLiveIdentity == nil)
    await activationGate.open()
  }

  @Test func zeroControllerActivationCommitsAnIdleBackendForFutureHotPlug() async {
    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(factory: factory, identifiers: [])

    #expect(await requestIdentity(server, .appleGameController))
    #expect(old.closeCountValue == 1)
    #expect(factory.values().count == 1)
    #expect(factory.values().first?.activationValues == [[]])
    #expect(server.userSpaceDispatcher === factory.values().first)
    #expect(server.compatibilityLiveIdentity == .appleGameController)
  }

  @Test func noncooperativeCandidateCloseCannotOverrunRollbackBudget() async {
    let defaults = UserDefaults.standard
    let identityKey = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let retryKey = ApplicationServiceServer.compatibilityRetrySnapshotDefaultsKey
    let priorIdentity = defaults.object(forKey: identityKey)
    let priorRetry = defaults.object(forKey: retryKey)
    defer {
      if let priorIdentity {
        defaults.set(priorIdentity, forKey: identityKey)
      } else {
        defaults.removeObject(forKey: identityKey)
      }
      if let priorRetry {
        defaults.set(priorRetry, forKey: retryKey)
      } else {
        defaults.removeObject(forKey: retryKey)
      }
    }
    let closeGate = CompatibilityTransitionGate()
    let factory = CompatibilityTransitionFactory()
    factory.activationFailures = [.appleGameController]
    factory.closeGates[.appleGameController] = closeGate
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)],
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 100_000_000,
        perControllerNanoseconds: 100_000_000,
        totalNanoseconds: 100_000_000,
        zeroControllerActivationNanoseconds: 100_000_000,
        feedbackNanoseconds: 100_000_000,
        candidateCloseNanoseconds: 100_000_000,
        rollbackStageNanoseconds: 100_000_000,
        rollbackActivationTotalNanoseconds: 100_000_000,
        zeroDeviceNanoseconds: 5_000_000
      )
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(old.closeCountValue == 1)
    #expect(factory.values().count == 1)
    #expect(server.userSpaceDispatcher == nil)
    await closeGate.open()
    while factory.values().first?.closeCountValue == 0 { await Task.yield() }
    #expect(factory.values().first?.closeCountValue == 1)
  }

  @Test func rapidIdentityRequestsSerializeAndCommitLastRequest() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let prior = defaults.object(forKey: key)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    let gate = CompatibilityTransitionGate()
    let factory = CompatibilityTransitionFactory()
    factory.firstActivationGate = gate
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )

    let first = Task { await requestIdentity(server, .appleGameController) }
    await factory.waitForCount(1)
    let second = Task { await requestIdentity(server, .sdl2_3) }
    while await server.compatibilityTransitionCoordinator.submissionCount() < 2 {
      await Task.yield()
    }
    let third = Task { await requestIdentity(server, .xbox360HID) }
    await gate.open()

    #expect(await first.value)
    #expect(await second.value)
    #expect(await third.value)
    #expect(server.compatibilityIdentity == .xbox360HID)
    #expect(server.userSpaceEnabled)
    #expect(old.closeCountValue == 1)
    #expect(factory.values().count == 3)
    #expect(factory.values().dropLast().allSatisfy { $0.closeCountValue == 1 })
    #expect(factory.values().last?.closeCountValue == 0)
  }

  @Test func zeroActivationDeadlineFailsDeterministicallyBeforeCommit() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let retryKey = ApplicationServiceServer.compatibilityRetrySnapshotDefaultsKey
    let prior = defaults.object(forKey: key)
    let priorRetry = defaults.object(forKey: retryKey)
    defaults.set(CompatibilityIdentity.genericHID.rawValue, forKey: key)
    defer {
      if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) }
      if let priorRetry {
        defaults.set(priorRetry, forKey: retryKey)
      } else {
        defaults.removeObject(forKey: retryKey)
      }
    }

    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)],
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 0,
        totalNanoseconds: 0
      )
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(old.closeCountValue == 1)
    #expect(factory.values().allSatisfy { $0.closeCountValue == 1 })
    #expect(factory.values().allSatisfy { $0.activationValues.isEmpty })
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
  }

  @Test func currentIdentityIsARealNoOp() async {
    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )

    #expect(await requestIdentity(server, .genericHID))
    #expect(factory.values().isEmpty)
    #expect(old.closeCountValue == 0)
    #expect(server.userSpaceDispatcher === old)
  }

  @Test func hangingActivationTimesOutAndCannotReplaceSuccessfulRollbackLate() async {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let gate = CompatibilityTransitionGate()
    let factory = CompatibilityTransitionFactory()
    factory.firstActivationGate = gate
    let (server, old) = transitionServer(
      factory: factory,
      identifiers: [identifier],
      timeouts: CompatibilityTransitionTimeouts(
        stageNanoseconds: 100_000_000,
        perControllerNanoseconds: 5_000_000,
        totalNanoseconds: 5_000_000,
        zeroControllerActivationNanoseconds: 5_000_000,
        feedbackNanoseconds: 100_000_000,
        candidateCloseNanoseconds: 100_000_000,
        rollbackStageNanoseconds: 100_000_000,
        rollbackActivationTotalNanoseconds: 100_000_000,
        zeroDeviceNanoseconds: 200_000_000
      )
    )

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(old.closeCountValue == 1)
    let rollback = factory.values().last
    #expect(factory.values().count == 2)
    #expect(server.userSpaceDispatcher === rollback)
    #expect(server.userSpaceEnabled)
    #expect(server.compatibilityTransitionSnapshot().liveIdentity == .genericHID)

    await gate.open()
    await Task.yield()
    #expect(server.userSpaceDispatcher === rollback)
    #expect(factory.values().first?.closeCountValue == 1)
  }

  @Test func startupActivationUsesTransactionAndNeutralActivation() async {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(factory: factory, identifiers: [identifier])

    #expect(await server.activateCompatibilityBackendForCurrentDevices())
    let candidate = factory.values().first
    #expect(candidate?.activationValues == [[identifier]])
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceDispatcher === candidate)
    #expect(server.userSpaceEnabled)
  }

  @Test func removalDuringBreakBeforeMakeCannotCommitGhostIdentifiers() async {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let snapshots = IdentifierSnapshotBox([[identifier], []])
    let factory = CompatibilityTransitionFactory()
    let (server, old) = transitionServer(factory: factory, identifiers: [identifier]) {
      snapshots.next()
    }

    #expect(await requestIdentity(server, .appleGameController) == false)
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceEnabled)
    #expect(server.compatibilityIdentity == .genericHID)
    #expect(factory.values().count == 2)
    #expect(factory.values().allSatisfy { $0.closeCountValue <= 1 })
  }

  @Test func shutdownCancelsTransitionAndPreventsPostShutdownCommit() async {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let gate = CompatibilityTransitionGate()
    let factory = CompatibilityTransitionFactory()
    factory.firstActivationGate = gate
    let (server, old) = transitionServer(factory: factory, identifiers: [identifier])
    let request = Task { await requestIdentity(server, .appleGameController) }
    await factory.waitForCount(1)

    let stop = Task { await server.stop() }
    while !server.isCompatibilityServerStopped() { await Task.yield() }
    await gate.open()
    await stop.value
    #expect(await request.value == false)
    #expect(old.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.userSpaceStatus == "off")
    #expect(server.compatibilityLiveIdentity == nil)
  }
}
