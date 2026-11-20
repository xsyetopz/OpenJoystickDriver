import Foundation

/// Bounds the one native send in flight with a single timer that stays armed across sends.
///
/// A sender publishes a report every few milliseconds, and each send would otherwise schedule and
/// cancel a timer of its own. The watchdog arms one timer when a send starts while none is armed,
/// and leaves it armed when the send ends. When it fires during a later send, it arms again for
/// what is left of that send's deadline, so a stream of reports costs one timer per deadline
/// period, and every send still expires no later than its own deadline.
final class ReportSendWatchdog: Sendable {
  /// The watchdog's view of the send in flight.
  private struct State: Sendable {
    /// Counts the sends; each send's number identifies it.
    var generation: UInt64 = 0
    /// When the send in flight started, in uptime nanoseconds; nil while no send runs.
    var activeStart: UInt64?
    /// Runs when the send in flight passes its deadline.
    var onExpire: (@Sendable () -> Void)?
    /// The send that the armed timer was armed for; nil while no timer is armed.
    var armedGeneration: UInt64?
    /// Stops the armed timer.
    var cancelTimer: DeadlineTimer.Cancel?
    /// Whether the watchdog stopped for good.
    var stopped = false
  }

  /// The state that the lock guards.
  private let state = Locked(State())
  /// The longest a send may run, in nanoseconds.
  private let deadlineNanoseconds: UInt64
  /// The timer that fires the deadline.
  private let timer: DeadlineTimer
  /// Reads the uptime clock in nanoseconds.
  private let now: @Sendable () -> UInt64

  /// Creates a watchdog that expires a send after `deadlineNanoseconds` on `timer`.
  init(
    deadlineNanoseconds: UInt64,
    timer: DeadlineTimer,
    now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) {
    self.deadlineNanoseconds = deadlineNanoseconds
    self.timer = timer
    self.now = now
  }

  /// Starts watching a send; `onExpire` runs once if it passes the deadline before ``end(_:)``.
  ///
  /// - Returns: The send's number, which ``end(_:)`` takes.
  func begin(onExpire: @escaping @Sendable () -> Void) -> UInt64 {
    let started = now()
    let (generation, arm) = state.withLock { state -> (UInt64, Bool) in
      state.generation &+= 1
      state.activeStart = started
      state.onExpire = onExpire
      guard !state.stopped, state.armedGeneration == nil else { return (state.generation, false) }
      state.armedGeneration = state.generation
      return (state.generation, true)
    }
    if arm { schedule(deadlineNanoseconds) }
    return generation
  }

  /// Stops watching the send numbered `generation`; the armed timer stays for the next send.
  func end(_ generation: UInt64) {
    state.withLock { state in
      guard state.generation == generation else { return }
      state.activeStart = nil
      state.onExpire = nil
    }
  }

  /// Cancels the armed timer and arms none again.
  func stop() {
    let cancel = state.withLock { state -> DeadlineTimer.Cancel? in
      state.stopped = true
      state.armedGeneration = nil
      state.onExpire = nil
      defer { state.cancelTimer = nil }
      return state.cancelTimer
    }
    cancel?()
  }

  /// Arms the timer to fire after `nanoseconds`.
  private func schedule(_ nanoseconds: UInt64) {
    let cancel = timer.schedule(nanoseconds) { [weak self] in self?.fire() }
    let stale = state.withLock { state -> Bool in
      guard !state.stopped else { return true }
      state.cancelTimer = cancel
      return false
    }
    if stale { cancel() }
  }

  /// Expires the send in flight when it is the one the timer was armed for or its deadline
  /// passed, arms again for a later send's remaining time, and disarms while no send runs.
  private func fire() {
    let current = now()
    enum Next {
      case idle
      case expire(@Sendable () -> Void)
      case rearm(UInt64)
    }
    let next = state.withLock { state -> Next in
      let armed = state.armedGeneration
      state.armedGeneration = nil
      state.cancelTimer = nil
      guard !state.stopped, let start = state.activeStart, let armed else { return .idle }
      let elapsed = current &- start
      if state.generation == armed || elapsed >= deadlineNanoseconds {
        let expire = state.onExpire
        state.activeStart = nil
        state.onExpire = nil
        return expire.map(Next.expire) ?? .idle
      }
      state.armedGeneration = state.generation
      return .rearm(deadlineNanoseconds - elapsed)
    }
    switch next {
    case .idle: break
    case .expire(let expire): expire()
    case .rearm(let remaining): schedule(remaining)
    }
  }
}
