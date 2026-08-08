import Foundation
import OpenJoystickDriverKit

extension RemappingOutputRouter {
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

  var tickerIsRunning: Bool { lock.withLock { tickerTask != nil } }

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
      lock.withLock { if shutdownAttempt?.id == attempt.id { shutdownAttempt = nil } }
      throw error
    }
  }

  func synchronizeControls(requiring permit: RemappingEmissionPermit?) async throws {
    let snapshot = lock.withLock { controls }
    try await core.apply(snapshot, requiring: permit)
  }

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

  private func tickerFinished(generation: UInt64) {
    lock.withLock {
      guard tickerGeneration == generation else { return }
      tickerTask = nil
      tickerDeadline = nil
    }
  }

  func updateControls(outputSuppressed: Bool? = nil, compatibilityOutputAllowed: Bool? = nil)
    -> RemappingRoutingControls
  {
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

  func setProfileTransactionGateActive(_ active: Bool) {
    let snapshot = lock.withLock { () -> RemappingRoutingControls in
      profileTransactionGateActive = active
      return controls
    }
    updateCompatibilitySuppression(controls: snapshot)
  }

  func updateCompatibilitySuppression(controls snapshot: RemappingRoutingControls) {
    let transactionSuppressed = lock.withLock { profileTransactionGateActive }
    compatibility.suppressOutput = Self.compatibilityIsSuppressed(snapshot) || transactionSuppressed
  }

  private static func compatibilityIsSuppressed(_ controls: RemappingRoutingControls) -> Bool {
    controls.outputSuppressed || !controls.compatibilityOutputAllowed
  }

  func outputLeaseIfOpen() throws -> RemappingEmissionLease? {
    if let lease = emissionBarrier.acquireLease() { return lease }
    if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
    return nil
  }
}
