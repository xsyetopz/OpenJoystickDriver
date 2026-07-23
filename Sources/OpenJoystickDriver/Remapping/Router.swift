import Dispatch
import Foundation
import OpenJoystickDriverKit

/// Exclusively selects compatibility output or system-input remapping per exact controller.
final class RemappingOutputRouter: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  typealias UptimeReader = @Sendable () -> UInt64
  typealias TickerSleeper = @Sendable (UInt64) async throws -> Void

  private let compatibility: any OutputDispatcher
  private let core: RemappingRoutingCore
  private let emissionBarrier: RemappingEmissionBarrier
  private let uptime: UptimeReader
  private let tickerIntervalNanoseconds: UInt64?
  private let tickerSleeper: TickerSleeper
  private let lock = NSLock()
  private var controls = RemappingRoutingControls(
    outputSuppressed: false,
    compatibilityOutputAllowed: true,
    revision: 0
  )
  private var tickerTask: Task<Void, Never>?
  private var tickerEnabled = false
  private var tickerGeneration: UInt64 = 0
  private var tickerSnapshotRevision: UInt64 = 0
  private var tickerDeadline: UInt64?
  private var profileTransactionGateActive = false
  private var shutdownAttempt: (id: UUID, task: Task<Void, any Error>)?
  private var terminalCleanupComplete = false

  var suppressOutput: Bool {
    get { lock.withLock { controls.outputSuppressed } }
    set {
      let snapshot = updateControls(outputSuppressed: newValue)
      updateCompatibilitySuppression(controls: snapshot)
      Task { [weak self] in
        guard let self else { return }
        guard let lease = try? outputLeaseIfOpen() else { return }
        defer { lease.finish() }
        try? await core.apply(snapshot, requiring: lease.permit)
        await reconcileTickerWithEngine()
      }
    }
  }

  init(
    library: RemappingProfileLibrary,
    engine: RemappingEventEngine,
    compatibility: any OutputDispatcher,
    foregroundApplication: any RemappingForegroundApplicationProviding,
    postEventAccess: any RemappingPostEventAccessProviding,
    tickerIntervalNanoseconds: UInt64? = 8_000_000,
    uptime: @escaping UptimeReader = { DispatchTime.now().uptimeNanoseconds },
    tickerSleeper: @escaping TickerSleeper = { try await Task.sleep(nanoseconds: $0) },
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void = { _ in }
  ) {
    self.compatibility = compatibility
    self.emissionBarrier = engine.emissionBarrier
    self.uptime = uptime
    self.tickerIntervalNanoseconds = tickerIntervalNanoseconds
    self.tickerSleeper = tickerSleeper
    self.core = RemappingRoutingCore(
      library: library,
      engine: engine,
      compatibility: compatibility,
      foregroundApplication: foregroundApplication,
      postEventAccess: postEventAccess,
      operationCheckpoint: operationCheckpoint
    )
  }

  deinit {
    tickerTask?.cancel()
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    do {
      try await dispatchCausally(events: events, from: identifier)
    } catch {
      // OutputDispatcher cannot surface errors. Callers that need causal failure
      // reporting use dispatchCausally or inspect the typed route status.
    }
  }

  func dispatchCausally(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier
  ) async throws {
    guard let lease = try outputLeaseIfOpen() else {
      try await core.recordConnectedIdentifierWhileOutputClosed(identifier)
      return
    }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      let snapshot = lock.withLock { controls }
      do {
        try await core.apply(snapshot, requiring: permit)
      } catch RemappingEventEngineError.outputSuspended {
        // A transaction still admits exact controller identity while blocking output.
      }
      try await core.dispatch(
        events: events,
        from: identifier,
        at: uptime(),
        requiring: permit
      )
    } catch {
      await reconcileTickerWithEngine()
      if error as? RemappingEventEngineError == .outputSuspended { return }
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func refresh(_ identifier: DeviceIdentifier) async throws {
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await synchronizeControls(requiring: permit)
      try await core.refresh(identifier, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func refreshModel(vendorID: UInt16, productID: UInt16) async throws {
    let permit: RemappingEmissionPermit?
    if let current = emissionBarrier.currentPermit() {
      permit = current
    } else {
      permit = await core.profileTransactionPermit()
    }
    do {
      try await synchronizeControls(requiring: permit)
      try await core.refreshModel(
        vendorID: vendorID,
        productID: productID,
        requiring: permit
      )
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func beginProfileTransaction() async throws -> RemappingProfileTransaction {
    let transaction = RemappingProfileTransaction()
    setProfileTransactionGateActive(true)
    let permit: RemappingEmissionPermit
    switch await emissionBarrier.suspend(owner: transaction.id) {
    case .admitted(let admittedPermit):
      permit = admittedPermit
    case .transactionAlreadyActive:
      await reconcileTickerWithEngine()
      throw RemappingOutputRoutingError.profileTransactionAlreadyActive
    case .terminated:
      await reconcileTickerWithEngine()
      throw RemappingOutputRoutingError.shutDown
    }
    do {
      try await synchronizeControls(requiring: permit)
      try await core.beginProfileTransaction(transaction, requiring: permit)
    } catch let beginError {
      if let routingError = beginError as? RemappingOutputRoutingError {
        switch routingError {
        case .profileTransactionAlreadyActive, .profileTransactionUnreconciled, .shutDown:
          await reconcileTickerWithEngine()
          throw routingError
        default:
          break
        }
      }
      do {
        try await core.rollBackProfileTransaction(transaction, requiring: permit)
      } catch let reconciliationError {
        let unreconciled = RemappingOutputRoutingError.profileTransactionUnreconciled(
          reconciliationError.localizedDescription
        )
        await core.markProfileTransactionUnreconciled(transaction, error: unreconciled)
        await reconcileTickerWithEngine()
        throw unreconciled
      }
      if emissionBarrier.resume(owner: transaction.id) {
        setProfileTransactionGateActive(false)
      }
      await reconcileTickerWithEngine()
      throw beginError
    }
    await reconcileTickerWithEngine()
    return transaction
  }

  func acceptProfileTransaction(_ transaction: RemappingProfileTransaction) async throws {
    let permit = emissionBarrier.transactionPermit(owner: transaction.id)
    do {
      try await core.acceptProfileTransaction(transaction, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    if emissionBarrier.resume(owner: transaction.id) {
      setProfileTransactionGateActive(false)
    }
    await reconcileTickerWithEngine()
  }

  func rollBackProfileTransaction(_ transaction: RemappingProfileTransaction) async throws {
    let permit = emissionBarrier.transactionPermit(owner: transaction.id)
    do {
      try await core.rollBackProfileTransaction(transaction, requiring: permit)
    } catch {
      if error as? RemappingOutputRoutingError == .shutDown {
        await reconcileTickerWithEngine()
        throw error
      }
      let unreconciled = RemappingOutputRoutingError.profileTransactionUnreconciled(
        error.localizedDescription
      )
      await core.markProfileTransactionUnreconciled(transaction, error: unreconciled)
      await reconcileTickerWithEngine()
      throw unreconciled
    }
    if emissionBarrier.resume(owner: transaction.id) {
      setProfileTransactionGateActive(false)
    }
    await reconcileTickerWithEngine()
  }

  func markProfileTransactionUnreconciled(
    _ transaction: RemappingProfileTransaction,
    detail: String
  ) async {
    guard !emissionBarrier.isTerminated else { return }
    let error = RemappingOutputRoutingError.profileTransactionUnreconciled(detail)
    await core.markProfileTransactionUnreconciled(transaction, error: error)
    await reconcileTickerWithEngine()
  }

  func recoverProfileTransaction() async throws {
    let permit = await core.profileTransactionPermit()
    do {
      try await core.recoverProfileTransaction(requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    if let permit, emissionBarrier.resume(permit) {
      setProfileTransactionGateActive(false)
    }
    await reconcileTickerWithEngine()
  }

  func refreshEligibility() async throws {
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await synchronizeControls(requiring: permit)
      try await core.refreshEligibility(requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func setOutputSuppressed(_ suppressed: Bool) async throws {
    let snapshot = updateControls(outputSuppressed: suppressed)
    updateCompatibilitySuppression(controls: snapshot)
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await core.apply(snapshot, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func setCompatibilityOutputAllowed(_ allowed: Bool) async throws {
    let snapshot = updateControls(compatibilityOutputAllowed: allowed)
    updateCompatibilitySuppression(controls: snapshot)
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await core.apply(snapshot, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  /// Applies the compatibility gate and causally re-evaluates application-scoped
  /// remapping after a foreground-consumer lifecycle notification.
  func foregroundStateDidChange(compatibilityOutputAllowed allowed: Bool) async throws {
    let snapshot = updateControls(compatibilityOutputAllowed: allowed)
    updateCompatibilitySuppression(controls: snapshot)
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await core.apply(
        snapshot,
        requiring: permit,
        refreshEligibilityWhenUnchanged: true
      )
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func tick(at uptimeNanoseconds: UInt64) async throws {
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await synchronizeControls(requiring: permit)
      try await core.tick(at: uptimeNanoseconds, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      if error as? RemappingEventEngineError == .outputSuspended { return }
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func status(for identifier: DeviceIdentifier) async -> RemappingRouteStatus? {
    let permit = emissionBarrier.currentPermit()
    try? await synchronizeControls(requiring: permit)
    try? await core.refreshEligibility(requiring: permit)
    await reconcileTickerWithEngine()
    return await core.status(for: identifier)
  }

  func statuses() async -> [RemappingRouteStatus] {
    let snapshot = await statusSnapshot()
    return snapshot.routes
  }

  func statusSnapshot() async -> RemappingRouterStatusSnapshot {
    let controls = lock.withLock { self.controls }
    let snapshot = await core.statusSnapshot(
      applying: controls,
      requiring: emissionBarrier.currentPermit()
    )
    await reconcileTickerWithEngine()
    return snapshot
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) {
    Task { [weak self] in
      guard let self else { return }
      try? await core.stopController(
        identifier,
        requiring: emissionBarrier.currentPermit()
      )
      await reconcileTickerWithEngine()
    }
  }

  func stopController(_ identifier: DeviceIdentifier) async throws {
    let permit = emissionBarrier.currentPermit()
    do {
      try await core.stopController(identifier, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func startTicker() {
    let shouldInspect = lock.withLock {
      tickerEnabled = tickerIntervalNanoseconds != nil
      return tickerEnabled
    }
    guard shouldInspect else { return }
    Task { [weak self] in await self?.reconcileTickerWithEngine() }
  }

  func stopTicker() {
    let task = lock.withLock { () -> Task<Void, Never>? in
      tickerEnabled = false
      tickerGeneration &+= 1
      defer {
        tickerTask = nil
        tickerDeadline = nil
      }
      return tickerTask
    }
    task?.cancel()
  }

  var tickerIsRunning: Bool {
    lock.withLock { tickerTask != nil }
  }

  func shutdown() async throws {
    setProfileTransactionGateActive(true)
    stopTicker()
    let attempt = lock.withLock { () -> (id: UUID, task: Task<Void, any Error>)? in
      guard !terminalCleanupComplete else { return nil }
      if let shutdownAttempt { return shutdownAttempt }
      let id = UUID()
      let task = Task { [emissionBarrier, core] in
        await emissionBarrier.terminate()
        try await core.shutdown()
      }
      let attempt = (id: id, task: task)
      shutdownAttempt = attempt
      return attempt
    }
    guard let attempt else { return }
    do {
      try await attempt.task.value
      lock.withLock {
        terminalCleanupComplete = true
        if shutdownAttempt?.id == attempt.id { shutdownAttempt = nil }
      }
    } catch {
      lock.withLock {
        if shutdownAttempt?.id == attempt.id { shutdownAttempt = nil }
      }
      throw error
    }
  }

  private func synchronizeControls(requiring permit: RemappingEmissionPermit?) async throws {
    let snapshot = lock.withLock { controls }
    try await core.apply(snapshot, requiring: permit)
  }

  private func reconcileTickerWithEngine() async {
    let enabled = lock.withLock { tickerEnabled }
    guard enabled, let continuousInterval = tickerIntervalNanoseconds else { return }
    let now = uptime()
    let snapshot = await core.schedulingSnapshot(
      after: now,
      continuousIntervalNanoseconds: continuousInterval
    )
    reconcileTicker(snapshot, observedAt: now)
  }

  private func reconcileTicker(
    _ snapshot: RemappingSchedulingSnapshot,
    observedAt uptimeNanoseconds: UInt64
  ) {
    let taskToCancel = lock.withLock { () -> Task<Void, Never>? in
      guard snapshot.revision >= tickerSnapshotRevision else { return nil }
      tickerSnapshotRevision = snapshot.revision
      guard tickerEnabled, let deadline = snapshot.nextTickUptimeNanoseconds
      else {
        tickerGeneration &+= 1
        defer {
          tickerTask = nil
          tickerDeadline = nil
        }
        return tickerTask
      }
      guard tickerDeadline != deadline || tickerTask == nil else { return nil }
      let previousTask = tickerTask
      tickerGeneration &+= 1
      let generation = tickerGeneration
      let sleeper = tickerSleeper
      let delay = deadline >= uptimeNanoseconds ? deadline - uptimeNanoseconds : 0
      let task = Task { [weak self] in
        do {
          try await sleeper(delay)
        } catch {
          self?.tickerFinished(generation: generation)
          return
        }
        guard let self else { return }
        await fireTicker(generation: generation)
      }
      tickerTask = task
      tickerDeadline = deadline
      return previousTask
    }
    taskToCancel?.cancel()
  }

  private func fireTicker(generation: UInt64) async {
    let isCurrent = lock.withLock {
      tickerEnabled && tickerGeneration == generation && tickerTask != nil
    }
    guard isCurrent else { return }
    guard let lease = try? outputLeaseIfOpen() else {
      tickerFinished(generation: generation)
      return
    }
    defer { lease.finish() }
    do {
      try await core.tick(at: uptime(), requiring: lease.permit)
    } catch {
      tickerFinished(generation: generation)
      return
    }
    tickerFinished(generation: generation)
    await reconcileTickerWithEngine()
  }

  private func tickerFinished(generation: UInt64) {
    lock.withLock {
      guard tickerGeneration == generation else { return }
      tickerTask = nil
      tickerDeadline = nil
    }
  }

  private func updateControls(
    outputSuppressed: Bool? = nil,
    compatibilityOutputAllowed: Bool? = nil
  ) -> RemappingRoutingControls {
    lock.withLock {
      controls = RemappingRoutingControls(
        outputSuppressed: outputSuppressed ?? controls.outputSuppressed,
        compatibilityOutputAllowed: compatibilityOutputAllowed
          ?? controls.compatibilityOutputAllowed,
        revision: controls.revision &+ 1
      )
      return controls
    }
  }

  private func setProfileTransactionGateActive(_ active: Bool) {
    let snapshot = lock.withLock { () -> RemappingRoutingControls in
      profileTransactionGateActive = active
      return controls
    }
    updateCompatibilitySuppression(controls: snapshot)
  }

  private func updateCompatibilitySuppression(controls snapshot: RemappingRoutingControls) {
    let transactionSuppressed = lock.withLock { profileTransactionGateActive }
    compatibility.suppressOutput = Self.compatibilityIsSuppressed(snapshot)
      || transactionSuppressed
  }

  private static func compatibilityIsSuppressed(_ controls: RemappingRoutingControls) -> Bool {
    controls.outputSuppressed || !controls.compatibilityOutputAllowed
  }

  private func outputLeaseIfOpen() throws -> RemappingEmissionLease? {
    if let lease = emissionBarrier.acquireLease() { return lease }
    if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
    return nil
  }
}
