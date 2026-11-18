import Foundation

/// Wakes the callers that wait for a feed's next host output command.
///
/// A waiter registers before it checks its condition, and a notify resumes every waiter of the
/// feed, so a command that arrives between the check and the wait still wakes it.
/// - Note: `@unchecked Sendable` because `lock` guards `waiters`.
final class VirtualFeedFeedbackSignal: @unchecked Sendable {
  /// Guards `waiters`.
  private let lock = NSLock()
  /// The suspended waiters, by feed token and then by waiter.
  private var waiters: [UUID: [UUID: CheckedContinuation<Void, Never>]] = [:]

  /// Suspends until ``notify(_:)`` runs for `token`, `timeout` seconds pass, or the calling task
  /// is cancelled; returns at once when `ready` is already true after the waiter registered.
  func wait(for token: UUID, timeout: TimeInterval, until ready: () -> Bool) async {
    let waiter = UUID()
    let timer = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
      self?.resume(waiter, of: token)
    }
    defer { timer.cancel() }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        lock.withLock { waiters[token, default: [:]][waiter] = continuation }
        if ready() || Task.isCancelled { resume(waiter, of: token) }
      }
    } onCancel: {
      resume(waiter, of: token)
    }
  }

  /// Resumes every waiter of `token`.
  func notify(_ token: UUID) {
    let resumed = lock.withLock { waiters.removeValue(forKey: token) }
    for continuation in (resumed ?? [:]).values { continuation.resume() }
  }

  /// Resumes one waiter once; later calls for it do nothing.
  private func resume(_ waiter: UUID, of token: UUID) {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      let found = waiters[token]?.removeValue(forKey: waiter)
      if waiters[token]?.isEmpty == true { waiters.removeValue(forKey: token) }
      return found
    }
    continuation?.resume()
  }
}

extension VirtualFeedRegistry {
  /// Suspends until the feed has a host output command that
  /// ``exchange(token:frames:countsAsActivity:)`` would return, the feed closes, `timeout` seconds
  /// pass, or the calling task is cancelled.
  ///
  /// Returns true when an exchange now has something to report: a waiting command or the feed's
  /// closure. The wait collects nothing and does not count as activity for the idle timeout.
  func waitForFeedback(token: UUID, timeout: TimeInterval) async -> Bool {
    await feedbackSignal.wait(for: token, timeout: timeout) {
      hasFeedbackToReport(token: token)
    }
    return hasFeedbackToReport(token: token)
  }
}
