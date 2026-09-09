import Foundation
import OpenJoystickDriverKit

final class AutomaticBackendSlot: @unchecked Sendable {
  let backend: any CompatibilityUserSpaceOutputDispatching
  private let lock = NSLock()
  private var leases = 0
  private var retired = false
  private var closed = false
  private var closeCompleted = false
  private var retirementWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []
  init(_ backend: any CompatibilityUserSpaceOutputDispatching) { self.backend = backend }
  func acquire() -> AutomaticBackendLease? {
    lock.withLock {
      guard !retired && !closed else { return nil }
      leases += 1
      return AutomaticBackendLease(self)
    }
  }
  func retireAndWait() async {
    let shouldClose = lock.withLock {
      retired = true
      return leases == 0
    }
    if shouldClose { await closeOnce() } else { await waitForCloseCompletion() }
  }
  func release() async {
    let shouldClose = lock.withLock { () -> Bool in
      leases -= 1
      return retired && leases == 0 && !closed
    }
    if shouldClose { await closeOnce() }
  }
  func closeOnce() async {
    let owner = lock.withLock { () -> Int in
      if closeCompleted { return 0 }
      if !closed {
        closed = true
        return 1
      }
      return 2
    }
    if owner == 1 {
      await backend.close()
      let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
        closeCompleted = true
        let result = retirementWaiters + closeWaiters
        retirementWaiters.removeAll()
        closeWaiters.removeAll()
        return result
      }
      waiters.forEach { $0.resume() }
    } else if owner == 2 {
      await waitForCloseCompletion()
    }
  }
  private func waitForCloseCompletion() async {
    await withCheckedContinuation { continuation in
      let complete = lock.withLock { () -> Bool in
        if closeCompleted { return true }
        closeWaiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

final class AutomaticBackendLease: @unchecked Sendable {
  private let slot: AutomaticBackendSlot
  private let lock = NSLock()
  private var released = false
  init(_ slot: AutomaticBackendSlot) { self.slot = slot }
  var backend: any CompatibilityUserSpaceOutputDispatching { slot.backend }
  func release() async {
    let shouldRelease = lock.withLock {
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { await slot.release() }
  }
}
