import Foundation
import OpenJoystickDriverKit

/// Owns one virtual output backend and closes it once, after its last lease is released.
final class AutomaticBackendSlot: Sendable {
  /// The lease and close state of the slot.
  private struct State {
    /// The number of leases that are out.
    var leases = 0
    /// Whether the slot admits no leases.
    var retired = false
    /// Whether the close has begun.
    var closed = false
    /// Whether the close has finished.
    var closeCompleted = false
    /// The task that closes the backend, shared by every caller.
    var nativeCloseTask: Task<Void, Never>?
    /// The callers that wait for retirement.
    var retirementWaiters: [CheckedContinuation<Void, Never>] = []
    /// The callers that wait for the close to finish.
    var closeWaiters: [CheckedContinuation<Void, Never>] = []
  }

  /// The backend that the slot owns.
  let backend: any VirtualOutputDispatching
  /// The state of the slot.
  private let state = Locked(State())

  /// Creates a slot for `backend`.
  init(_ backend: any VirtualOutputDispatching) { self.backend = backend }

  /// Returns a lease on the backend, or nil once the slot is retired or closed.
  func acquire() -> AutomaticBackendLease? {
    state.withLock { state in
      guard !state.retired && !state.closed else { return nil }
      state.leases += 1
      return AutomaticBackendLease(self)
    }
  }

  /// Revoke admission immediately.
  ///
  /// A stalled native close must not block other controllers.
  @discardableResult
  func retireAndWait() async -> Bool {
    let shouldClose = state.withLock { state in
      state.retired = true
      return state.leases == 0
    }
    if shouldClose {
      await closeOnce()
      return true
    }
    do {
      try await withVirtualOutputTimeout(
        VirtualOutputTransitionTimeouts.standard.candidateCloseNanoseconds,
        clock: .system,
        error: .candidateCloseTimedOut
      ) { [self] in await waitForCloseCompletion() }
      return true
    } catch {
      _ = beginClose()
      return false
    }
  }

  /// Gives up one lease and closes the backend when it was the last of a retired slot.
  func release() async {
    let shouldClose = state.withLock { state -> Bool in
      state.leases -= 1
      return state.retired && state.leases == 0 && !state.closed
    }
    if shouldClose { await closeOnce() }
  }

  /// Closes the backend; every caller shares one close.
  func closeOnce() async {
    let task = beginClose()
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  /// Starts the close of the backend, or returns the close that is under way.
  @discardableResult
  private func beginClose() -> Task<Void, Never> {
    let backend = self.backend
    return state.withLock { state in
      if let nativeCloseTask = state.nativeCloseTask { return nativeCloseTask }
      state.closed = true
      let task = Task { [weak self] in
        await backend.close()
        let waiters =
          self?.state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.closeCompleted = true
            let result = state.retirementWaiters + state.closeWaiters
            state.retirementWaiters.removeAll()
            state.closeWaiters.removeAll()
            return result
          } ?? []
        for waiter in waiters { waiter.resume() }
      }
      state.nativeCloseTask = task
      return task
    }
  }

  /// Returns once the close of the backend has finished.
  func waitForCloseCompletion() async {
    await withCheckedContinuation { continuation in
      let complete = state.withLock { state -> Bool in
        if state.closeCompleted { return true }
        state.closeWaiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

/// A claim on the backend of a slot that keeps it from closing until it is released.
final class AutomaticBackendLease: Sendable {
  /// The slot that granted the lease.
  private let slot: AutomaticBackendSlot
  /// Whether the lease was released.
  private let released = Locked(false)

  /// Creates a lease on `slot`.
  init(_ slot: AutomaticBackendSlot) { self.slot = slot }

  /// The backend that the lease keeps open.
  var backend: any VirtualOutputDispatching { slot.backend }

  /// Releases the lease once; later calls do nothing.
  func release() async {
    let shouldRelease = released.withLock { released in
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { await slot.release() }
  }
}
