import Foundation
import OpenJoystickDriverKit

/// Answers post-event preflights from the last sample of another probe, and refreshes that sample
/// off the caller's thread once it is older than ``maxAgeNanoseconds``.
///
/// Every input report and every posted key or pointer event reads the permission, and one
/// `CGPreflightPostEventAccess` call blocks about 15 ms on a round trip to the system's privacy
/// services. A cached answer keeps that cost off the input path; a change in System Settings shows
/// within about one refresh period.
final class CachedPostEventAccessProbe: CoreGraphicsPostEventAccessProbing {
  /// The last sample and whether a refresh is under way.
  private struct Sample: Sendable {
    /// The last answer; nil before the first sample and after a request.
    var granted: Bool?
    /// The uptime of the last sample, in nanoseconds.
    var sampledAt: UInt64 = 0
    /// Whether a refresh is scheduled or running.
    var refreshing = false
    /// Counts the requests, so a read started before one does not replace the answer after it.
    var generation: UInt64 = 0
  }

  /// The age past which a preflight schedules a refresh, in nanoseconds.
  let maxAgeNanoseconds: UInt64
  /// The probe that reads the permission.
  private let source: any CoreGraphicsPostEventAccessProbing
  /// The clock, in nanoseconds of uptime.
  private let now: @Sendable () -> UInt64
  /// Runs a refresh away from the caller.
  private let schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
  /// The last sample.
  private let sample = Locked(Sample())

  /// Creates a cache of `source` whose answers are refreshed once older than `maxAgeNanoseconds`.
  init(
    source: any CoreGraphicsPostEventAccessProbing,
    maxAgeNanoseconds: UInt64 = 1_000_000_000,
    now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
      DispatchQueue.global(qos: .utility).async(execute: $0)
    }
  ) {
    self.source = source
    self.maxAgeNanoseconds = maxAgeNanoseconds
    self.now = now
    self.schedule = schedule
  }

  /// Returns the cached answer, reading `source` in place only when no answer is cached.
  func preflight() -> Bool {
    let current = now()
    let (cached, refresh) = sample.withLock { sample -> (Bool?, Bool) in
      guard let granted = sample.granted else { return (nil, false) }
      let stale = current &- sample.sampledAt >= maxAgeNanoseconds
      guard stale, !sample.refreshing else { return (granted, false) }
      sample.refreshing = true
      return (granted, true)
    }
    if refresh { schedule { [self] in _ = read() } }
    return cached ?? read()
  }

  /// Asks `source` for access; the next preflight reads `source` again.
  @discardableResult
  func request() -> Bool {
    defer {
      sample.withLock {
        $0.granted = nil
        $0.refreshing = false
        $0.generation &+= 1
      }
    }
    return source.request()
  }

  /// Reads `source` and caches its answer unless a request came in during the read.
  private func read() -> Bool {
    let generation = sample.withLock { $0.generation }
    let granted = source.preflight()
    let sampledAt = now()
    sample.withLock {
      guard $0.generation == generation else { return }
      $0.granted = granted
      $0.sampledAt = sampledAt
      $0.refreshing = false
    }
    return granted
  }
}
