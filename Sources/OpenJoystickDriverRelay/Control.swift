import Foundation

struct DriverKitStateBridgeMetrics: Sendable, Equatable {
  let workerStarts: Int
  let maximumConcurrentWorkers: Int
  let requestedRevision: UInt64
  let appliedRevision: UInt64
}

final class DriverKitStateBridge: @unchecked Sendable {
  private struct State {
    var desiredValue = false
    var pendingTrueEdge = false
    var requestedRevision: UInt64 = 0
    var appliedRevision: UInt64 = 0
    var workerRunning = false
    var workerStarts = 0
    var activeWorkers = 0
    var maximumConcurrentWorkers = 0
    var waiters: [(UInt64, CheckedContinuation<Void, Never>)] = []
  }

  private let apply: @Sendable (Bool, UInt64) async -> Void
  private let preservesTrueEdges: Bool
  private let lock = NSLock()
  private var state = State()

  init(
    preservesTrueEdges: Bool = false,
    apply: @escaping @Sendable (Bool, UInt64) async -> Void
  ) {
    self.preservesTrueEdges = preservesTrueEdges
    self.apply = apply
  }

  @discardableResult func request(_ value: Bool) -> UInt64 {
    let request = lock.withLock { () -> (Bool, UInt64) in
      state.desiredValue = value
      if preservesTrueEdges, value { state.pendingTrueEdge = true }
      state.requestedRevision &+= 1
      guard !state.workerRunning else { return (false, state.requestedRevision) }
      state.workerRunning = true
      state.workerStarts += 1
      state.activeWorkers += 1
      state.maximumConcurrentWorkers = max(state.maximumConcurrentWorkers, state.activeWorkers)
      return (true, state.requestedRevision)
    }
    if request.0 { Task { await drain() } }
    return request.1
  }

  func wait(untilApplied revision: UInt64) async {
    if lock.withLock({ state.appliedRevision >= revision }) { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard state.appliedRevision < revision else { return true }
        state.waiters.append((revision, continuation))
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  func metrics() -> DriverKitStateBridgeMetrics {
    lock.withLock {
      DriverKitStateBridgeMetrics(
        workerStarts: state.workerStarts,
        maximumConcurrentWorkers: state.maximumConcurrentWorkers,
        requestedRevision: state.requestedRevision,
        appliedRevision: state.appliedRevision
      )
    }
  }

  private func drain() async {
    while true {
      let request = lock.withLock { () -> (Bool, UInt64) in
        if preservesTrueEdges, state.pendingTrueEdge {
          state.pendingTrueEdge = false
          return (true, state.requestedRevision)
        }
        return (state.desiredValue, state.requestedRevision)
      }
      await apply(request.0, request.1)

      let completion = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
        let needsAnotherApplication =
          state.requestedRevision != request.1
          || state.desiredValue != request.0
          || (preservesTrueEdges && state.pendingTrueEdge)
        if !needsAnotherApplication {
          state.appliedRevision = max(state.appliedRevision, request.1)
        }
        let appliedRevision = state.appliedRevision
        let ready = state.waiters.filter { $0.0 <= appliedRevision }.map(\.1)
        state.waiters.removeAll { $0.0 <= appliedRevision }
        guard !needsAnotherApplication else { return (false, ready) }
        state.workerRunning = false
        state.activeWorkers -= 1
        return (true, ready)
      }
      completion.1.forEach { $0.resume() }
      if completion.0 { return }
    }
  }
}
