import Dispatch
import Foundation
import OpenJoystickDriverKit

/// Exclusively selects compatibility output or system-input remapping per exact controller.
final class RemappingOutputRouter: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  typealias UptimeReader = @Sendable () -> UInt64
  typealias TickerSleeper = @Sendable (UInt64) async throws -> Void

  let compatibility: any OutputDispatcher
  let core: RemappingRoutingCore
  let emissionBarrier: RemappingEmissionBarrier
  let uptime: UptimeReader
  let tickerIntervalNanoseconds: UInt64?
  let tickerSleeper: TickerSleeper
  let lock = NSLock()
  var controls = RemappingRoutingControls(
    outputSuppressed: false,
    compatibilityOutputAllowed: true,
    revision: 0
  )
  var tickerTask: Task<Void, Never>?
  var tickerEnabled = false
  var tickerGeneration: UInt64 = 0
  var tickerSnapshotRevision: UInt64 = 0
  var tickerDeadline: UInt64?
  var profileTransactionGateActive = false
  var shutdownAttempt: (id: UUID, task: Task<Void, any Error>)?
  var terminalCleanupComplete = false

  var suppressOutput: Bool {
    get { lock.withLock { controls.outputSuppressed } }
    set { _ = updateControls(outputSuppressed: newValue) }
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

  deinit { tickerTask?.cancel() }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    do { try await dispatchCausally(events: events, from: identifier) } catch {
      // OutputDispatcher cannot surface errors. Callers that need causal failure
      // reporting use dispatchCausally or inspect the typed route status.
    }
  }

  func dispatchCausally(events: [ControllerEvent], from identifier: DeviceIdentifier) async throws {
    guard let lease = try outputLeaseIfOpen() else {
      try await core.recordConnectedIdentifierWhileOutputClosed(identifier)
      return
    }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      let snapshot = lock.withLock { controls }
      do { try await core.apply(snapshot, requiring: permit) } catch RemappingEventEngineError
        .outputSuspended
      {
        // A transaction still admits exact controller identity while blocking output.
      }
      try await core.dispatch(events: events, from: identifier, at: uptime(), requiring: permit)
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
      try await core.refreshModel(vendorID: vendorID, productID: productID, requiring: permit)
    } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }

  func beginProfileTransaction() async throws -> RemappingProfileTransaction {
    let transaction = RemappingProfileTransaction()
    await setProfileTransactionGateActive(true)
    let permit: RemappingEmissionPermit
    switch await emissionBarrier.suspend(owner: transaction.id) {
    case .admitted(let admittedPermit): permit = admittedPermit
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
        default: break
        }
      }
      do { try await core.rollBackProfileTransaction(transaction, requiring: permit) } catch let
        reconciliationError
      {
        let unreconciled = RemappingOutputRoutingError.profileTransactionUnreconciled(
          reconciliationError.localizedDescription
        )
        await core.markProfileTransactionUnreconciled(transaction, error: unreconciled)
        await reconcileTickerWithEngine()
        throw unreconciled
      }
      if emissionBarrier.resume(owner: transaction.id) {
        await setProfileTransactionGateActive(false)
      }
      await reconcileTickerWithEngine()
      throw beginError
    }
    await reconcileTickerWithEngine()
    return transaction
  }

  func acceptProfileTransaction(_ transaction: RemappingProfileTransaction) async throws {
    let permit = emissionBarrier.transactionPermit(owner: transaction.id)
    do { try await core.acceptProfileTransaction(transaction, requiring: permit) } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    if emissionBarrier.resume(owner: transaction.id) {
      await setProfileTransactionGateActive(false)
    }
    await reconcileTickerWithEngine()
  }

  func rollBackProfileTransaction(_ transaction: RemappingProfileTransaction) async throws {
    let permit = emissionBarrier.transactionPermit(owner: transaction.id)
    do { try await core.rollBackProfileTransaction(transaction, requiring: permit) } catch {
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
      await setProfileTransactionGateActive(false)
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
    do { try await core.recoverProfileTransaction(requiring: permit) } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    if let permit, emissionBarrier.resume(permit) { await setProfileTransactionGateActive(false) }
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
    try await applyControlsSnapshot(snapshot)
  }

  func setCompatibilityOutputAllowed(_ allowed: Bool) async throws {
    let snapshot = updateControls(compatibilityOutputAllowed: allowed)
    try await applyControlsSnapshot(snapshot)
  }

  /// Applies the compatibility gate and causally re-evaluates application-scoped
  /// remapping after a foreground-consumer lifecycle notification.
  func foregroundStateDidChange(compatibilityOutputAllowed allowed: Bool) async throws {
    let snapshot = updateControls(compatibilityOutputAllowed: allowed)
    try await applyControlsSnapshot(snapshot, refreshEligibilityWhenUnchanged: true)
  }

  private func applyControlsSnapshot(
    _ snapshot: RemappingRoutingControls,
    refreshEligibilityWhenUnchanged: Bool = false
  ) async throws {
    await updateCompatibilitySuppression(controls: snapshot)
    guard let lease = try outputLeaseIfOpen() else { return }
    defer { lease.finish() }
    let permit = lease.permit
    do {
      try await core.apply(
        snapshot,
        requiring: permit,
        refreshEligibilityWhenUnchanged: refreshEligibilityWhenUnchanged
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

  func controllerDidStop(_ identifier: DeviceIdentifier) async {
    try? await core.stopController(identifier, requiring: emissionBarrier.currentPermit())
    await reconcileTickerWithEngine()
  }

  func stopController(_ identifier: DeviceIdentifier) async throws {
    let permit = emissionBarrier.currentPermit()
    do { try await core.stopController(identifier, requiring: permit) } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }
}
