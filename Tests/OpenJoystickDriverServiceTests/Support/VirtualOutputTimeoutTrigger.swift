import Foundation

@testable import OpenJoystickDriverService

/// A transition clock whose timeouts fire only when a test calls `expire`, so a test decides when
/// an operation counts as timed out instead of racing a real timer against a loaded machine.
final class VirtualOutputTimeoutTrigger: @unchecked Sendable {
  private struct Pending {
    let nanoseconds: UInt64
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var pending: [UUID: Pending] = [:]

  var clock: VirtualOutputTransitionClock {
    VirtualOutputTransitionClock(now: { 0 }, sleep: { try await self.sleep($0) })
  }

  /// Fires the first timer that waits for `nanoseconds`, once it exists.
  func expire(nanoseconds: UInt64) async {
    while true {
      let fired = lock.withLock { () -> Pending? in
        guard let key = pending.first(where: { $0.value.nanoseconds == nanoseconds })?.key else {
          return nil
        }
        return pending.removeValue(forKey: key)
      }
      if let fired {
        fired.continuation.resume()
        return
      }
      await Task.yield()
    }
  }

  private func sleep(_ nanoseconds: UInt64) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let cancelled = lock.withLock { () -> Bool in
          if Task.isCancelled { return true }
          pending[id] = Pending(nanoseconds: nanoseconds, continuation: continuation)
          return false
        }
        if cancelled { continuation.resume(throwing: CancellationError()) }
      }
    } onCancel: {
      let removed = lock.withLock { pending.removeValue(forKey: id) }
      removed?.continuation.resume(throwing: CancellationError())
    }
  }
}
