import Foundation
import OpenJoystickDriverKit

/// The time a ``VirtualFeedRegistry`` reads and waits on.
///
/// Production waits on a timer thread (``DeadlineTimer``) rather than the cooperative pool, so an
/// idle or hung-send deadline is not delayed by a pool its own feeds may be starving. Tests inject
/// a manual clock and move time by hand.
struct VirtualFeedClock: Sendable {
  /// Seconds on a monotonic scale.
  let now: @Sendable () -> TimeInterval
  /// Suspends until `now()` reaches the given time; throws `CancellationError` when cancelled.
  let sleep: @Sendable (_ until: TimeInterval) async throws -> Void

  /// The uptime clock, whose sleep waits on a timer thread.
  static let system = Self(
    now: { ProcessInfo.processInfo.systemUptime },
    sleep: { time in
      let remaining = time - ProcessInfo.processInfo.systemUptime
      guard remaining > 0 else { return }
      try await DeadlineTimer.dispatch.sleep(
        nanoseconds: UInt64(min(remaining, 1e9) * 1_000_000_000)
      )
    }
  )
}
