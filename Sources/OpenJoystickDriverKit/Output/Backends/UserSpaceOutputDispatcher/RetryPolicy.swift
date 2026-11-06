import Foundation

/// Spaces out the attempts to create a virtual device after a failure.
struct UserSpaceDeviceCreationRetryPolicy {
  /// The pause after a failure, in nanoseconds, unless the caller sets one.
  static let defaultDelayNanoseconds: UInt64 = 5_000_000_000

  /// The pause after a failure, in nanoseconds.
  let delayNanoseconds: UInt64
  /// The uptime from which the next attempt is allowed, in nanoseconds.
  private(set) var nextAttemptNanoseconds: UInt64 = 0

  /// Creates a policy with a pause of `delayNanoseconds`.
  init(delayNanoseconds: UInt64 = Self.defaultDelayNanoseconds) {
    self.delayNanoseconds = delayNanoseconds
  }

  /// Whether an attempt is allowed at the uptime `now`.
  func permitsAttempt(at now: UInt64) -> Bool { now >= nextAttemptNanoseconds }

  /// Records a failure at `now`; the next attempt waits for the pause, and an overflow waits
  /// indefinitely.
  mutating func recordFailure(at now: UInt64) {
    let (nextAttempt, overflow) = now.addingReportingOverflow(delayNanoseconds)
    nextAttemptNanoseconds = overflow ? UInt64.max : nextAttempt
  }
}
