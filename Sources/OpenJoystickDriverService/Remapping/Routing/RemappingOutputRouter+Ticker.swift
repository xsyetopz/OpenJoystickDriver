import Foundation
import OpenJoystickDriverKit

extension RemappingOutputRouter {
  /// Turns the ticker on when it has an interval and schedules the next tick.
  func startTicker() {
    let shouldInspect = lock.withLock {
      tickerEnabled = tickerIntervalNanoseconds != nil
      return tickerEnabled
    }
    guard shouldInspect else { return }
    Task { [weak self] in await self?.reconcileTickerWithEngine() }
  }

  /// Turns the ticker off and cancels its task.
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

  /// Whether a tick is scheduled.
  var tickerIsRunning: Bool { lock.withLock { tickerTask != nil } }

  /// Stops the router: ends the ticker, terminates the emission barrier and shuts the core down.
  ///
  /// Concurrent calls share one attempt, and a later call returns at once after a finished one.
  ///
  /// - Throws: The failure of the core's shutdown.
  func shutdown() async throws {
    await setProfileTransactionGateActive(true)
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
      lock.withLock { if shutdownAttempt?.id == attempt.id { shutdownAttempt = nil } }
      throw error
    }
  }

  /// Applies the current controls to the core.
  func synchronizeControls(requiring permit: RemappingEmissionPermit?) async throws {
    let snapshot = lock.withLock { controls }
    try await core.apply(snapshot, requiring: permit)
  }

  /// Asks the core when the next tick is due and schedules or cancels the ticker task.
  func reconcileTickerWithEngine() async {
    let enabled = lock.withLock { tickerEnabled }
    guard enabled, let continuousInterval = tickerIntervalNanoseconds else { return }
    let now = uptime()
    let snapshot = await core.schedulingSnapshot(
      after: now,
      continuousIntervalNanoseconds: continuousInterval
    )
    reconcileTicker(snapshot, observedAt: now)
  }

  /// Replaces the ticker task so that it fires at the deadline of `snapshot`, or cancels it when no
  /// tick is due.
  ///
  /// A snapshot older than the latest one is ignored.
  private func reconcileTicker(
    _ snapshot: RemappingSchedulingSnapshot,
    observedAt uptimeNanoseconds: UInt64
  ) {
    let taskToCancel = lock.withLock { () -> Task<Void, Never>? in
      guard snapshot.revision >= tickerSnapshotRevision else { return nil }
      tickerSnapshotRevision = snapshot.revision
      guard tickerEnabled, let deadline = snapshot.nextTickUptimeNanoseconds else {
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
        do { try await sleeper(delay) } catch {
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

  /// Ticks the core when the task of `generation` is current.
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
    do { try await core.tick(at: uptime(), requiring: lease.permit) } catch {
      tickerFinished(generation: generation)
      return
    }
    tickerFinished(generation: generation)
    await reconcileTickerWithEngine()
  }

  /// Clears the ticker task when `generation` is current.
  private func tickerFinished(generation: UInt64) {
    lock.withLock {
      guard tickerGeneration == generation else { return }
      tickerTask = nil
      tickerDeadline = nil
    }
  }

  /// Stores controls with `outputSuppressed` and a next revision, and returns them.
  func updateControls(outputSuppressed: Bool) -> RemappingRoutingControls {
    lock.withLock {
      controls = RemappingRoutingControls(
        outputSuppressed: outputSuppressed,
        revision: controls.revision &+ 1
      )
      return controls
    }
  }

  /// Sets whether a profile transaction keeps the virtual output suppressed.
  func setProfileTransactionGateActive(_ active: Bool) async {
    let snapshot = lock.withLock { () -> RemappingRoutingControls in
      profileTransactionGateActive = active
      return controls
    }
    await updateOutputSuppression(controls: snapshot)
  }

  /// Tells the virtual output and the remapping output control whether they are suppressed.
  ///
  /// Output is suppressed when `snapshot` suppresses it or a profile transaction holds the gate.
  func updateOutputSuppression(controls snapshot: RemappingRoutingControls) async {
    let transactionSuppressed = lock.withLock { profileTransactionGateActive }
    await virtualOutput.setOutputSuppressed(snapshot.outputSuppressed || transactionSuppressed)
    if let controlling = virtualOutput as? any RemappingGamepadOutputControlling {
      await controlling.setRemappingOutputSuppressed(
        snapshot.outputSuppressed || transactionSuppressed
      )
    }
  }

  /// Returns a lease on the emission barrier, or nil when output is closed.
  ///
  /// - Throws: ``RemappingOutputRoutingError/shutDown`` when the barrier is terminated.
  func outputLeaseIfOpen() throws -> RemappingEmissionLease? {
    if let lease = emissionBarrier.acquireLease() { return lease }
    if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
    return nil
  }
}
