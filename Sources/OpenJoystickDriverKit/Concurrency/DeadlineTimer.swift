import Foundation

/// Fires a handler once after a delay, on a thread that does not belong to the cooperative pool.
///
/// A deadline written as `Task.sleep` runs its expiry on the cooperative pool, so a pool whose
/// threads are all busy or blocked delivers the expiry late, and a deadline that exists to bound a
/// hung call is itself held up by the hang. Each timer here owns a serial dispatch queue, so its
/// expiry runs at once. Tests inject a manual timer to drive a deadline without real time.
package struct DeadlineTimer: Sendable {
  /// Cancels a scheduled deadline.
  package typealias Cancel = @Sendable () -> Void
  /// The handler that runs when a deadline passes.
  package typealias Fire = @Sendable () -> Void

  /// Schedules `fire` after `nanoseconds` and returns a closure that cancels it.
  package let schedule: @Sendable (_ nanoseconds: UInt64, _ fire: @escaping Fire) -> Cancel

  /// Creates a timer from a `schedule` function.
  package init(
    schedule: @escaping @Sendable (_ nanoseconds: UInt64, _ fire: @escaping Fire) -> Cancel
  ) {
    self.schedule = schedule
  }

  /// The timer production code uses: one dispatch timer on its own serial queue per deadline.
  package static let dispatch = Self { nanoseconds, fire in
    let queue = DispatchQueue(label: "com.openjoystickdriver.deadline")
    let source = DispatchSource.makeTimerSource(queue: queue)
    source.schedule(
      deadline: .now() + .nanoseconds(Int(clamping: nanoseconds)),
      leeway: .nanoseconds(0)
    )
    source.setEventHandler {
      source.cancel()
      fire()
    }
    source.resume()
    return { source.cancel() }
  }
}

extension DeadlineTimer {
  /// Suspends for `nanoseconds` and resumes when the timer fires, or throws `CancellationError`
  /// as soon as the calling task is cancelled.
  package func sleep(nanoseconds: UInt64) async throws {
    let gate = SleepGate()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let cancelTimer = schedule(nanoseconds) { gate.fire() }
        gate.arm(continuation, cancelTimer: cancelTimer)
      }
    } onCancel: {
      gate.cancel()
    }
  }
}

/// Resumes one sleeping task exactly once, whichever of the timer, a cancellation, or an early
/// arrival comes first.
private final class SleepGate: @unchecked Sendable {
  /// What ended the sleep.
  private enum Outcome {
    /// The timer fired.
    case fired
    /// The task was cancelled.
    case cancelled
  }

  /// Guards the stored values.
  private let lock = NSLock()
  /// The sleeping task; nil before `arm(_:cancelTimer:)` and after it resumes.
  private var continuation: CheckedContinuation<Void, any Error>?
  /// Cancels the timer; nil before `arm(_:cancelTimer:)`.
  private var cancelTimer: DeadlineTimer.Cancel?
  /// The outcome that arrived before the task armed the gate.
  private var early: Outcome?

  /// Stores the sleeping task and its timer cancellation, or finishes at once when an outcome
  /// arrived early.
  func arm(
    _ continuation: CheckedContinuation<Void, any Error>,
    cancelTimer: @escaping DeadlineTimer.Cancel
  ) {
    let outcome = lock.withLock { () -> Outcome? in
      if let early { return early }
      self.continuation = continuation
      self.cancelTimer = cancelTimer
      return nil
    }
    guard let outcome else { return }
    cancelTimer()
    resume(continuation, outcome)
  }

  /// Ends the sleep because the timer fired.
  func fire() { finish(.fired) }

  /// Ends the sleep because the task was cancelled.
  func cancel() { finish(.cancelled) }

  /// Records the first `outcome`, cancels the timer and resumes the sleeping task.
  private func finish(_ outcome: Outcome) {
    let pending = lock.withLock {
      () -> (CheckedContinuation<Void, any Error>, DeadlineTimer.Cancel?)? in
      guard early == nil else { return nil }
      early = outcome
      guard let continuation else { return nil }
      defer {
        self.continuation = nil
        cancelTimer = nil
      }
      return (continuation, cancelTimer)
    }
    guard let (continuation, cancelTimer) = pending else { return }
    cancelTimer?()
    resume(continuation, outcome)
  }

  /// Resumes `continuation` normally for a fired timer, or with `CancellationError` for a
  /// cancellation.
  private func resume(_ continuation: CheckedContinuation<Void, any Error>, _ outcome: Outcome) {
    switch outcome {
    case .fired: continuation.resume()
    case .cancelled: continuation.resume(throwing: CancellationError())
    }
  }
}
