import CryptoKit
import Dispatch
import Foundation
import OpenJoystickDriverKit

/// Exclusively selects virtual gamepad output or system-input remapping per exact controller.
final class RemappingOutputRouter: OutputDispatcher, ControllerLifecycleListener,
  ControllerInputOwnershipListener, ObservedInputDemand, @unchecked Sendable
{
  /// Reads the uptime in nanoseconds.
  typealias UptimeReader = @Sendable () -> UInt64
  /// Sleeps for the given number of nanoseconds.
  typealias TickerSleeper = @Sendable (UInt64) async throws -> Void

  /// The virtual gamepad output.
  let virtualOutput: any OutputDispatcher
  /// The core that holds the routes and applies every operation.
  let core: RemappingRoutingCore
  /// The engine's barrier that gates output; operations take a lease from it.
  let emissionBarrier: RemappingEmissionBarrier
  /// Reads the uptime that the ticker and dispatch use.
  let uptime: UptimeReader
  /// The interval of the continuous tick, or nil when the ticker is off.
  let tickerIntervalNanoseconds: UInt64?
  /// Sleeps until the next tick.
  let tickerSleeper: TickerSleeper
  /// The lock that guards the controls and the ticker state.
  let lock = NSLock()
  /// The router-wide output controls.
  var controls = RemappingRoutingControls(outputSuppressed: false, revision: 0)
  /// The task that sleeps until the next tick.
  var tickerTask: Task<Void, Never>?
  /// Whether the ticker is on.
  var tickerEnabled = false
  /// The number of the current ticker task; a task of an earlier number is ignored.
  var tickerGeneration: UInt64 = 0
  /// The revision of the latest scheduling snapshot applied to the ticker.
  var tickerSnapshotRevision: UInt64 = 0
  /// The uptime in nanoseconds of the pending tick.
  var tickerDeadline: UInt64?
  /// Whether a profile transaction keeps the virtual output suppressed.
  var profileTransactionGateActive = false
  /// The shutdown in progress, with its ID.
  var shutdownAttempt: (id: UUID, task: Task<Void, any Error>)?
  /// Whether the shutdown finished.
  var terminalCleanupComplete = false

  /// Whether all remapping output is suppressed; setting it publishes the controls.
  var suppressOutput: Bool {
    get { lock.withLock { controls.outputSuppressed } }
    set { _ = updateControls(outputSuppressed: newValue) }
  }

  /// Creates the router over the library, engine and output, with the ticker interval, clock and
  /// sleeper.
  init(
    library: RemappingProfileLibrary,
    engine: RemappingEventEngine,
    virtualOutput: any OutputDispatcher,
    foregroundApplication: any RemappingForegroundApplicationProviding,
    postEventAccess: any RemappingPostEventAccessProviding,
    installationKey: SymmetricKey,
    tickerIntervalNanoseconds: UInt64? = 8_000_000,
    uptime: @escaping UptimeReader = { DispatchTime.now().uptimeNanoseconds },
    tickerSleeper: @escaping TickerSleeper = { try await Task.sleep(nanoseconds: $0) },
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void = { _ in }
  ) {
    self.virtualOutput = virtualOutput
    self.emissionBarrier = engine.emissionBarrier
    self.uptime = uptime
    self.tickerIntervalNanoseconds = tickerIntervalNanoseconds
    self.tickerSleeper = tickerSleeper
    self.core = RemappingRoutingCore(
      library: library,
      engine: engine,
      virtualOutput: virtualOutput,
      foregroundApplication: foregroundApplication,
      postEventAccess: postEventAccess,
      installationKey: installationKey,
      operationCheckpoint: operationCheckpoint
    )
  }

  deinit { tickerTask?.cancel() }

  /// Only a remapping route consumes a native controller's input; virtual gamepad output never
  /// publishes for it.
  func wantsObservedInput(from identifier: LogicalControllerID) -> Bool {
    core.observedInputDemand.contains(identifier)
  }

  /// Passes the input ownership of `identifier` to the core and reschedules the ticker.
  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async {
    do { try await core.updateInputOwnership(ownership, for: identifier) } catch {
      // Engine failures are retained in the typed route status by the core.
    }
    await reconcileTickerWithEngine()
  }

  /// Dispatches `event` and drops any failure, which the route status keeps.
  func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    do { try await dispatchCausally(.input(event), from: identifier) } catch {
      // OutputDispatcher cannot surface errors. Callers that need causal failure
      // reporting use dispatchCausally or inspect the typed route status.
    }
  }

  /// `onPublished` runs once a virtual gamepad route's virtual device has the report; a remapping
  /// route publishes through the engine and reports no publication.
  func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    try await dispatchCausally(.input(event), from: identifier, onPublished: onPublished)
  }

  /// Dispatches the activation of `identifier` and drops any failure, which the route status keeps.
  func activateOutput(for identifier: LogicalControllerID) async {
    do { try await dispatchCausally(.activation, from: identifier) } catch {
      // As for dispatch: the typed route status retains the failure.
    }
  }

  /// Applies the controls and routes `input` of `identifier`.
  ///
  /// When output is closed, the call only records the controller.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` or ``RemappingEventEngineError`` that the core
  ///   reports; an output suspension is not thrown.
  func dispatchCausally(
    _ input: RemappingRoutedInput,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void = {}
  ) async throws {
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
      try await core.dispatch(
        input,
        from: identifier,
        at: uptime(),
        requiring: permit,
        onPublished: onPublished
      )
    } catch {
      await reconcileTickerWithEngine()
      if error as? RemappingEventEngineError == .outputSuspended { return }
      throw error
    }
    await reconcileTickerWithEngine()
  }

  /// Selects the output of `identifier` again from the active profile.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the library or engine fails.
  func refresh(_ identifier: LogicalControllerID) async throws {
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

  /// Pairs the Joy-Cons `left` and `right` under `profile` and returns the session ID.
  ///
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when output is closed, and the
  ///   failures of ``RemappingRoutingCore/pairJoyCons(left:right:profile:requiring:)``.
  func pairJoyCons(
    left: LogicalControllerID,
    right: LogicalControllerID,
    profile: RemappingProfile
  ) async throws -> UUID {
    guard let lease = try outputLeaseIfOpen() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    try await synchronizeControls(requiring: lease.permit)
    let sessionID = try await core.pairJoyCons(
      left: left,
      right: right,
      profile: profile,
      requiring: lease.permit
    )
    await reconcileTickerWithEngine()
    return sessionID
  }

  /// Ends the Joy-Con pair `sessionID`.
  ///
  /// - Throws: ``RemappingEventEngineError/outputSuspended`` when output is closed, and the
  ///   failures of ``RemappingRoutingCore/unpairJoyCons(_:requiring:)``.
  func unpairJoyCons(_ sessionID: UUID) async throws {
    guard let lease = try outputLeaseIfOpen() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    try await synchronizeControls(requiring: lease.permit)
    try await core.unpairJoyCons(sessionID, requiring: lease.permit)
    await reconcileTickerWithEngine()
  }

  /// Selects the output again for every controller of the model `vendorID` and `productID`.
  ///
  /// This works while a profile transaction holds the output.
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

  /// Opens a profile transaction and suspends output.
  ///
  /// A failure rolls the transaction back, except when the failure says that a transaction is
  /// active, unreconciled or the router is shut down.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when a transaction is active or unreconciled, the
  ///   router is shut down, or the rollback fails.
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

  /// Ends `transaction` by installing its routes, then resumes output.
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

  /// Ends `transaction` by reloading the routes from the library, then resumes output.
  ///
  /// - Throws: ``RemappingOutputRoutingError/profileTransactionUnreconciled(_:)`` when the reload
  ///   fails.
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

  /// Marks `transaction` as unreconciled with `detail`.
  func markProfileTransactionUnreconciled(
    _ transaction: RemappingProfileTransaction,
    detail: String
  ) async {
    guard !emissionBarrier.isTerminated else { return }
    let error = RemappingOutputRoutingError.profileTransactionUnreconciled(detail)
    await core.markProfileTransactionUnreconciled(transaction, error: error)
    await reconcileTickerWithEngine()
  }

  /// Retries the reconciliation of an unreconciled transaction and resumes output when it succeeds.
  func recoverProfileTransaction() async throws {
    let permit = await core.profileTransactionPermit()
    do { try await core.recoverProfileTransaction(requiring: permit) } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    if let permit, emissionBarrier.resume(permit) { await setProfileTransactionGateActive(false) }
    await reconcileTickerWithEngine()
  }

  /// Recomputes the eligibility of every route.
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

  /// Advances the engine to `uptimeNanoseconds`.
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

  /// Returns the status of the route of `identifier` after it refreshes the eligibility.
  func status(for identifier: LogicalControllerID) async -> RemappingRouteStatus? {
    let permit = emissionBarrier.currentPermit()
    try? await synchronizeControls(requiring: permit)
    try? await core.refreshEligibility(requiring: permit)
    await reconcileTickerWithEngine()
    return await core.status(for: identifier)
  }

  /// Returns the status of every route.
  func statuses() async -> [RemappingRouteStatus] {
    let snapshot = await statusSnapshot()
    return snapshot.routes
  }

  /// Returns the routes and the Joy-Con pairs after it applies the controls.
  func statusSnapshot() async -> RemappingRouterStatusSnapshot {
    let controls = lock.withLock { self.controls }
    let snapshot = await core.statusSnapshot(
      applying: controls,
      requiring: emissionBarrier.currentPermit()
    )
    await reconcileTickerWithEngine()
    return snapshot
  }

  /// Stops the route of `identifier`; the lifecycle listener drops any failure.
  func controllerDidStop(_ identifier: LogicalControllerID) async {
    try? await core.stopController(identifier, requiring: emissionBarrier.currentPermit())
    await reconcileTickerWithEngine()
  }

  /// Stops the route of `identifier`.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` that the core reports.
  func stopController(_ identifier: LogicalControllerID) async throws {
    let permit = emissionBarrier.currentPermit()
    do { try await core.stopController(identifier, requiring: permit) } catch {
      await reconcileTickerWithEngine()
      throw error
    }
    await reconcileTickerWithEngine()
  }
}
