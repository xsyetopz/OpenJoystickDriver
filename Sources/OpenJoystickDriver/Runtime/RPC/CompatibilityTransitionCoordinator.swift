import Foundation
import OpenJoystickDriverKit

struct CompatibilityTransitionTimeouts: Sendable {
  static let standard = Self(
    stageNanoseconds: 2_000_000_000,
    perControllerNanoseconds: 2_000_000_000,
    totalNanoseconds: 10_000_000_000,
    zeroControllerActivationNanoseconds: 2_000_000_000,
    feedbackNanoseconds: 2_000_000_000,
    candidateCloseNanoseconds: 2_000_000_000,
    rollbackStageNanoseconds: 2_000_000_000,
    rollbackActivationTotalNanoseconds: 10_000_000_000,
    zeroDeviceNanoseconds: 20_000_000_000
  )

  let stageNanoseconds: UInt64
  let perControllerNanoseconds: UInt64
  let totalNanoseconds: UInt64
  let zeroControllerActivationNanoseconds: UInt64
  let feedbackNanoseconds: UInt64
  let candidateCloseNanoseconds: UInt64
  let rollbackStageNanoseconds: UInt64
  let rollbackActivationTotalNanoseconds: UInt64
  let zeroDeviceNanoseconds: UInt64

  init(
    stageNanoseconds: UInt64,
    perControllerNanoseconds: UInt64,
    totalNanoseconds: UInt64,
    zeroControllerActivationNanoseconds: UInt64 = 2_000_000_000,
    feedbackNanoseconds: UInt64 = 2_000_000_000,
    candidateCloseNanoseconds: UInt64 = 2_000_000_000,
    rollbackStageNanoseconds: UInt64 = 2_000_000_000,
    rollbackActivationTotalNanoseconds: UInt64 = 10_000_000_000,
    zeroDeviceNanoseconds: UInt64 = 20_000_000_000
  ) {
    self.stageNanoseconds = stageNanoseconds
    self.perControllerNanoseconds = perControllerNanoseconds
    self.totalNanoseconds = totalNanoseconds
    self.zeroControllerActivationNanoseconds = zeroControllerActivationNanoseconds
    self.feedbackNanoseconds = feedbackNanoseconds
    self.candidateCloseNanoseconds = candidateCloseNanoseconds
    self.rollbackStageNanoseconds = rollbackStageNanoseconds
    self.rollbackActivationTotalNanoseconds = rollbackActivationTotalNanoseconds
    self.zeroDeviceNanoseconds = zeroDeviceNanoseconds
  }

  func activationNanoseconds(for count: Int) -> UInt64 {
    guard count > 0 else { return zeroControllerActivationNanoseconds }
    let perController = perControllerNanoseconds.multipliedReportingOverflow(by: UInt64(count))
    return min(perController.overflow ? UInt64.max : perController.partialValue, totalNanoseconds)
  }

  func rollbackActivationNanoseconds(for count: Int) -> UInt64 {
    guard count > 0 else { return zeroControllerActivationNanoseconds }
    let perController = perControllerNanoseconds.multipliedReportingOverflow(by: UInt64(count))
    return min(
      perController.overflow ? UInt64.max : perController.partialValue,
      rollbackActivationTotalNanoseconds
    )
  }
}

struct CompatibilityTransitionClock: Sendable {
  static let system = Self(
    now: { DispatchTime.now().uptimeNanoseconds },
    sleep: { nanoseconds in try await Task.sleep(nanoseconds: nanoseconds) }
  )

  let now: @Sendable () -> UInt64
  let sleep: @Sendable (UInt64) async throws -> Void
}

enum CompatibilityTransitionError: Error, Sendable {
  case stageTimedOut
  case feedbackTimedOut
  case candidateCloseTimedOut
  case activationTimedOut
  case rollbackStageTimedOut
  case rollbackTimedOut
  case zeroDeviceIntervalTimedOut
  case serverStopped
}

private func withCompatibilityTimeout<Value: Sendable>(
  _ timeout: UInt64,
  clock: CompatibilityTransitionClock,
  error: CompatibilityTransitionError,
  operation: @escaping @Sendable () async throws -> Value,
  onLateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
) async throws -> Value {
  guard timeout > 0 else { throw error }

  let stream = AsyncThrowingStream<Value, Error> { continuation in
    let operationTask = Task.detached {
      do {
        let result = try await operation()
        switch continuation.yield(result) {
        case .enqueued: continuation.finish()
        case .dropped, .terminated:
          await onLateSuccess(result)
          continuation.finish()
        @unknown default: continuation.finish()
        }
      } catch { continuation.finish(throwing: error) }
    }
    let timerTask = Task.detached {
      do {
        try await clock.sleep(timeout)
        continuation.finish(throwing: error)
      } catch {
        // Cancellation only stops the timer.
      }
    }
    continuation.onTermination = { _ in
      operationTask.cancel()
      timerTask.cancel()
    }
  }
  var iterator = stream.makeAsyncIterator()
  guard let result = try await iterator.next() else { throw CancellationError() }
  return result
}

private final class CompatibilityTransitionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  var isStopped: Bool { lock.withLock { stopped } }
  func stop() { lock.withLock { stopped = true } }
}

actor CompatibilityTransitionCoordinator {
  private var tail: Task<Bool, Never>?
  private let cancellation = CompatibilityTransitionCancellation()
  private var submittedCount = 0

  func enqueue(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
    guard !cancellation.isStopped else { return false }
    submittedCount += 1
    let previous = tail
    let cancellation = self.cancellation
    let next = Task {
      _ = await previous?.value
      guard !Task.isCancelled, !cancellation.isStopped else { return false }
      return await operation()
    }
    tail = next
    return await next.value
  }

  func stop() {
    cancellation.stop()
    tail?.cancel()
    tail = nil
  }

  func submissionCount() -> Int { submittedCount }
}

final class CompatibilityFeedbackGate: @unchecked Sendable {
  private let deviceManager: DeviceManager
  private let lock = NSLock()
  private var accepting = true
  private var generation: UInt64 = 0
  private var active = 0
  private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(deviceManager: DeviceManager) { self.deviceManager = deviceManager }

  func submit(identifier: DeviceIdentifier, command: VirtualRumbleCommand) {
    let token = UUID()
    let currentGeneration = lock.withLock { () -> UInt64? in
      guard accepting else { return nil }
      active += 1
      return generation
    }
    guard let currentGeneration else { return }
    let task = Task { [weak self] in
      guard let self, self.isCurrent(currentGeneration) else {
        self?.finish(token)
        return
      }
      _ = await self.deviceManager.sendRumble(
        for: identifier,
        left: command.left,
        right: command.right,
        lt: command.leftTrigger,
        rt: command.rightTrigger,
        durationMs: command.durationMs
      )
      self.finish(token)
    }
    let shouldCancel = lock.withLock { () -> Bool in
      cancellationHandlers[token] = { task.cancel() }
      return !accepting || generation != currentGeneration
    }
    if shouldCancel { task.cancel() }
  }

  func quiesceAndNeutralize(
    _ identifiers: [DeviceIdentifier],
    timeout: UInt64 = CompatibilityTransitionTimeouts.standard.feedbackNanoseconds,
    clock: CompatibilityTransitionClock = .system,
    resumeWhenComplete: Bool = false
  ) async -> Bool {
    let (wasAccepting, cancellations) = lock.withLock {
      let wasAccepting = accepting
      accepting = false
      generation &+= 1
      let cancellations = Array(cancellationHandlers.values)
      cancellationHandlers.removeAll()
      if active == 0 {
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
      }
      return (wasAccepting, cancellations)
    }
    cancellations.forEach { $0() }
    do {
      try await withCompatibilityTimeout(timeout, clock: clock, error: .feedbackTimedOut) {
        await self.waitForIdle()
      }
    } catch { return false }
    for identifier in identifiers {
      do {
        try await withCompatibilityTimeout(timeout, clock: clock, error: .feedbackTimedOut) {
          _ = await self.deviceManager.sendRumble(
            for: identifier,
            left: 0,
            right: 0,
            lt: 0,
            rt: 0,
            durationMs: 0
          )
        }
      } catch { return false }
    }
    if resumeWhenComplete && wasAccepting { resume() }
    return true
  }

  func resume() {
    lock.withLock {
      generation &+= 1
      accepting = true
    }
  }

  private func isCurrent(_ generation: UInt64) -> Bool {
    lock.withLock { accepting && self.generation == generation }
  }

  private func finish(_ token: UUID) {
    let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      cancellationHandlers.removeValue(forKey: token)
      active = max(0, active - 1)
      guard active == 0 else { return [] }
      let waiters = self.waiters
      self.waiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }

  private func waitForIdle() async {
    await withCheckedContinuation { continuation in
      let complete = lock.withLock { () -> Bool in
        guard active > 0 else { return true }
        waiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

struct CompatibilityTransitionSnapshot: Sendable {
  let requestedIdentity: CompatibilityIdentity
  let persistedIdentity: CompatibilityIdentity
  let liveIdentity: CompatibilityIdentity?
  let enabled: Bool
  let dispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  let closeSlot: CompatibilityBackendCloseSlot?
}

struct CompatibilityRetrySnapshot: Codable, Equatable, Sendable {
  let requestedIdentity: CompatibilityIdentity
  let priorProfileIdentity: CompatibilityIdentity
  let phase: CompatibilityTransitionPhase
}

enum CompatibilityTransitionPhase: String, Codable, Equatable, Sendable {
  case stage
  case feedbackQuiescence
  case candidateClose
  case activation
  case rollbackStage
  case rollbackActivation
  case zeroDeviceInterval
}

final class CompatibilityBackendCloseSlot: @unchecked Sendable {
  let backend: any CompatibilityUserSpaceOutputDispatching
  private let lock = NSLock()
  private var closeTask: Task<Void, Never>?

  init(_ backend: any CompatibilityUserSpaceOutputDispatching) { self.backend = backend }

  func close(
    timeout: UInt64,
    clock: CompatibilityTransitionClock,
    error: CompatibilityTransitionError = .candidateCloseTimedOut
  ) async -> Bool {
    let task = lock.withLock { () -> Task<Void, Never> in
      if let closeTask { return closeTask }
      let backend = self.backend
      let task = Task.detached { await backend.close() }
      closeTask = task
      return task
    }
    do {
      try await withCompatibilityTimeout(timeout, clock: clock, error: error) { await task.value }
      return true
    } catch { return false }
  }
}

extension ApplicationServiceServer {
  func activateCompatibilityBackendForCurrentDevices() async -> Bool {
    await compatibilityTransitionCoordinator.enqueue { [weak self] in
      guard let self else { return false }
      return await self.performCompatibilityIdentityTransition(
        to: self.requestedIdentity(),
        force: true
      )
    }
  }

  func performCompatibilityIdentityTransition(
    to identity: CompatibilityIdentity,
    force: Bool = false,
    removePersistedIdentityOnCommit: Bool = false
  ) async -> Bool {
    guard !isCompatibilityServerStopped() else { return false }
    let prior = compatibilityTransitionSnapshot()
    if !force, prior.requestedIdentity == identity, prior.liveIdentity == identity, prior.enabled,
      prior.dispatcher != nil
    {
      return true
    }

    let candidate: UserSpaceDispatcherBuild
    do {
      candidate = try await stageCompatibilityDispatcher(
        identity: identity,
        timeout: compatibilityTransitionTimeouts.stageNanoseconds
      )
    } catch { return false }

    guard !isCompatibilityServerStopped() else {
      _ = await closeCompatibilityBackend(candidate.dispatcher, slot: candidate.closeSlot)
      return false
    }
    let identifiers = await connectedIdentifiers()
    guard
      await feedbackGate.quiesceAndNeutralize(
        identifiers,
        timeout: compatibilityTransitionTimeouts.feedbackNanoseconds,
        clock: compatibilityTransitionClock
      )
    else {
      _ = await closeCompatibilityBackend(candidate.dispatcher, slot: candidate.closeSlot)
      return false
    }
    var zeroDeviceStarted: UInt64?
    if let old = prior.dispatcher {
      userSpaceLock.withLock { dispatcher.setBackend(nil) }
      let closed = await closeCompatibilityBackend(old, slot: prior.closeSlot)
      guard closed else {
        _ = await closeCompatibilityBackend(candidate.dispatcher, slot: candidate.closeSlot)
        installUnavailableCompatibilityState(
          phase: .candidateClose,
          requestedIdentity: identity,
          priorProfileIdentity: prior.liveIdentity ?? prior.requestedIdentity
        )
        return false
      }
      zeroDeviceStarted = compatibilityTransitionClock.now()
    }

    do {
      let zeroDeviceRemaining = zeroDeviceStarted.map {
        remainingNanoseconds(
          since: $0,
          within: compatibilityTransitionTimeouts.zeroDeviceNanoseconds
        )
      }
      guard zeroDeviceRemaining != 0 else {
        throw CompatibilityTransitionError.zeroDeviceIntervalTimedOut
      }
      let activationTimeout = min(
        compatibilityTransitionTimeouts.activationNanoseconds(for: identifiers.count),
        zeroDeviceRemaining ?? UInt64.max
      )
      let activated = try await activateCompatibilityDispatcher(
        candidate.dispatcher,
        for: identifiers,
        timeout: activationTimeout
      )
      let reconciled = await connectedIdentifiers()
      guard activated, reconciled == identifiers, !isCompatibilityServerStopped() else {
        throw CompatibilityTransitionError.serverStopped
      }
      guard
        commitCompatibilityDispatcher(
          candidate,
          identity: identity,
          identifiers: reconciled,
          removePersistedIdentity: removePersistedIdentityOnCommit
        )
      else {
        _ = await closeCompatibilityBackend(candidate.dispatcher, slot: candidate.closeSlot)
        return false
      }
      feedbackGate.resume()
      return true
    } catch {
      guard
        await closeCompatibilityBackendWithinZeroDeviceBudget(
          candidate.dispatcher,
          slot: candidate.closeSlot,
          zeroDeviceStarted: zeroDeviceStarted
        )
      else {
        installUnavailableCompatibilityState(
          phase: .zeroDeviceInterval,
          requestedIdentity: identity,
          priorProfileIdentity: prior.liveIdentity ?? prior.requestedIdentity
        )
        return false
      }
      guard !isCompatibilityServerStopped() else { return false }
      guard prior.dispatcher != nil else {
        installUnavailableCompatibilityState(
          phase: .activation,
          requestedIdentity: identity,
          priorProfileIdentity: prior.liveIdentity ?? prior.requestedIdentity
        )
        return false
      }
      let rollbackIdentifiers = await connectedIdentifiers()
      if await rollbackCompatibilityDispatcher(
        identity: prior.liveIdentity ?? prior.requestedIdentity,
        identifiers: rollbackIdentifiers,
        prior: prior,
        requestedIdentityAfterFailure: identity,
        zeroDeviceStarted: zeroDeviceStarted
      ) {
        feedbackGate.resume()
      }
      return false
    }
  }

  private func stageCompatibilityDispatcher(identity: CompatibilityIdentity, timeout: UInt64)
    async throws -> UserSpaceDispatcherBuild
  {
    try await withCompatibilityTimeout(
      timeout,
      clock: compatibilityTransitionClock,
      error: .stageTimedOut
    ) {
      try self.buildUserSpaceDispatcher(identity: identity)
    } onLateSuccess: { candidate in
      _ = await self.closeCompatibilityBackend(candidate.dispatcher, slot: candidate.closeSlot)
    }
  }

  private func activateCompatibilityDispatcher(
    _ candidate: any CompatibilityUserSpaceOutputDispatching,
    for identifiers: [DeviceIdentifier],
    timeout: UInt64
  ) async throws -> Bool {
    guard !identifiers.isEmpty else {
      let zeroControllerTimeout = min(
        timeout,
        compatibilityTransitionTimeouts.zeroControllerActivationNanoseconds
      )
      try await withCompatibilityTimeout(
        zeroControllerTimeout,
        clock: compatibilityTransitionClock,
        error: .activationTimedOut
      ) { try await candidate.activate(for: []) }
      return true
    }
    if let scoped = candidate as? any CompatibilityUserSpaceOutputControllerActivating {
      let started = compatibilityTransitionClock.now()
      for identifier in identifiers {
        let elapsed = elapsedNanoseconds(since: started)
        let remaining = timeout > elapsed ? timeout - elapsed : 0
        let controllerTimeout = min(
          remaining,
          compatibilityTransitionTimeouts.perControllerNanoseconds
        )
        try await withCompatibilityTimeout(
          controllerTimeout,
          clock: compatibilityTransitionClock,
          error: .activationTimedOut
        ) { try await scoped.activate(controller: identifier) }
      }
      return true
    }
    try await withCompatibilityTimeout(
      timeout,
      clock: compatibilityTransitionClock,
      error: .activationTimedOut
    ) { try await candidate.activate(for: identifiers) }
    return true
  }

  private func rollbackCompatibilityDispatcher(
    identity: CompatibilityIdentity,
    identifiers: [DeviceIdentifier],
    prior: CompatibilityTransitionSnapshot,
    requestedIdentityAfterFailure: CompatibilityIdentity,
    zeroDeviceStarted: UInt64?
  ) async -> Bool {
    var candidate: UserSpaceDispatcherBuild?
    do {
      let staged = try await stageCompatibilityDispatcher(
        identity: identity,
        timeout: min(
          compatibilityTransitionTimeouts.rollbackStageNanoseconds,
          zeroDeviceStarted.map {
            remainingNanoseconds(
              since: $0,
              within: compatibilityTransitionTimeouts.zeroDeviceNanoseconds
            )
          } ?? UInt64.max
        )
      )
      candidate = staged
      let timeout = min(
        compatibilityTransitionTimeouts.rollbackActivationNanoseconds(for: identifiers.count),
        zeroDeviceStarted.map {
          remainingNanoseconds(
            since: $0,
            within: compatibilityTransitionTimeouts.zeroDeviceNanoseconds
          )
        } ?? UInt64.max
      )
      guard timeout > 0 else { throw CompatibilityTransitionError.zeroDeviceIntervalTimedOut }
      let activated = try await activateCompatibilityDispatcher(
        staged.dispatcher,
        for: identifiers,
        timeout: timeout
      )
      let reconciled = await connectedIdentifiers()
      guard activated, reconciled == identifiers, !isCompatibilityServerStopped() else {
        throw CompatibilityTransitionError.rollbackTimedOut
      }
      guard
        commitCompatibilityDispatcher(
          staged,
          identity: identity,
          identifiers: reconciled,
          persistedIdentity: prior.persistedIdentity,
          requestedIdentity: prior.requestedIdentity
        )
      else { throw CompatibilityTransitionError.serverStopped }
      return true
    } catch {
      guard
        await closeCompatibilityBackendWithinZeroDeviceBudget(
          candidate?.dispatcher,
          slot: candidate?.closeSlot,
          zeroDeviceStarted: zeroDeviceStarted
        )
      else {
        installUnavailableCompatibilityState(
          phase: .zeroDeviceInterval,
          requestedIdentity: requestedIdentityAfterFailure,
          priorProfileIdentity: prior.liveIdentity ?? prior.requestedIdentity
        )
        return false
      }
      guard !isCompatibilityServerStopped() else { return false }
      installUnavailableCompatibilityState(
        phase: .rollbackActivation,
        requestedIdentity: requestedIdentityAfterFailure,
        priorProfileIdentity: prior.liveIdentity ?? prior.requestedIdentity
      )
      return false
    }
  }

  private func commitCompatibilityDispatcher(
    _ build: UserSpaceDispatcherBuild,
    identity: CompatibilityIdentity,
    identifiers: [DeviceIdentifier],
    persistedIdentity: CompatibilityIdentity? = nil,
    requestedIdentity: CompatibilityIdentity? = nil,
    removePersistedIdentity: Bool = false
  ) -> Bool {
    userSpaceLock.withLock {
      guard !compatibilityServerStopped else { return false }
      dispatcher.setBackend(build.dispatcher)
      userSpaceDispatcher = build.dispatcher
      userSpaceCloseSlot = build.closeSlot
      userSpaceAutomaticGeneration = build.automaticGeneration
      pendingAutomaticTransitionGeneration = nil
      userSpaceEnabled = true
      userSpaceStatus = build.dispatcher.status
      compatibilityLiveIdentity = identity
      compatibilityIdentity = requestedIdentity ?? identity
      let persisted = persistedIdentity ?? identity
      persistedCompatibilityIdentity = persisted
      compatibilityRetrySnapshot = nil
      Self.persistCompatibilityRetrySnapshot(nil)
      if removePersistedIdentity {
        UserDefaults.standard.removeObject(forKey: Self.compatibilityIdentityDefaultsKey)
      } else {
        UserDefaults.standard.set(persisted.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
      }
      return true
    }
  }

  private func installUnavailableCompatibilityState(
    phase: CompatibilityTransitionPhase,
    requestedIdentity: CompatibilityIdentity? = nil,
    priorProfileIdentity: CompatibilityIdentity? = nil
  ) {
    userSpaceLock.withLock {
      dispatcher.setBackend(nil)
      userSpaceDispatcher = nil
      userSpaceCloseSlot = nil
      userSpaceAutomaticGeneration = nil
      pendingAutomaticTransitionGeneration = nil
      userSpaceEnabled = false
      compatibilityLiveIdentity = nil
      if let requestedIdentity {
        compatibilityIdentity = requestedIdentity
        persistedCompatibilityIdentity = requestedIdentity
        UserDefaults.standard.set(
          requestedIdentity.rawValue,
          forKey: Self.compatibilityIdentityDefaultsKey
        )
        let retrySnapshot = CompatibilityRetrySnapshot(
          requestedIdentity: requestedIdentity,
          priorProfileIdentity: priorProfileIdentity ?? requestedIdentity,
          phase: phase
        )
        compatibilityRetrySnapshot = retrySnapshot
        Self.persistCompatibilityRetrySnapshot(retrySnapshot)
      }
      userSpaceStatus = "error: compatibility \(phase.rawValue) failed; output unavailable"
    }
  }

  private func elapsedNanoseconds(since start: UInt64) -> UInt64 {
    let now = compatibilityTransitionClock.now()
    return now >= start ? now - start : 0
  }

  private func remainingNanoseconds(since start: UInt64, within limit: UInt64) -> UInt64 {
    let elapsed = elapsedNanoseconds(since: start)
    return elapsed >= limit ? 0 : limit - elapsed
  }

  private func closeCompatibilityBackendWithinZeroDeviceBudget(
    _ backend: (any CompatibilityUserSpaceOutputDispatching)?,
    slot: CompatibilityBackendCloseSlot?,
    zeroDeviceStarted: UInt64?
  ) async -> Bool {
    guard backend != nil else { return true }
    let remaining = zeroDeviceStarted.map {
      remainingNanoseconds(since: $0, within: compatibilityTransitionTimeouts.zeroDeviceNanoseconds)
    }
    let timeout = min(
      compatibilityTransitionTimeouts.candidateCloseNanoseconds,
      remaining ?? UInt64.max
    )
    return await closeCompatibilityBackend(
      backend,
      slot: slot,
      timeout: timeout,
      error: zeroDeviceStarted == nil ? .candidateCloseTimedOut : .zeroDeviceIntervalTimedOut
    )
  }

  private func connectedIdentifiers() async -> [DeviceIdentifier] {
    var seen = Set<DeviceIdentifier>()
    return (await connectedIdentifierProvider()).filter { seen.insert($0).inserted }
  }

  private func requestedIdentity() -> CompatibilityIdentity {
    userSpaceLock.withLock { compatibilityIdentity }
  }
}
