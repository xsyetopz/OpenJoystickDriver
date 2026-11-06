import Foundation

/// The outcome of one attempt to read a HID feature report.
enum HIDFeatureReadAttempt: Sendable {
  /// The read gave a report that the caller accepts.
  case accepted
  /// The read gave no usable report; another attempt may follow.
  case retry
  /// The pipeline lifetime that the attempt serves ended; no attempt may follow.
  case stopped
}

/// Bounded retries of a HID feature-report read; each attempt must revalidate the pipeline
/// lifetime it serves.
enum HIDFeatureReadRetry {
  /// Runs `attempt` up to `maximumAttempts` times, at most 3, and waits `delayNanoseconds` between
  /// attempts.
  ///
  /// A cancelled task or a sleep that fails stops the run.
  ///
  /// - Parameters:
  ///   - maximumAttempts: The most attempts to make, clamped to `0...3`.
  ///   - delayNanoseconds: The wait before every attempt after the first.
  ///   - attempt: Makes one attempt.
  /// - Returns: ``HIDFeatureReadAttempt/accepted`` or ``HIDFeatureReadAttempt/stopped`` as soon
  ///   as an attempt or the task reports it, and ``HIDFeatureReadAttempt/retry`` when every
  ///   attempt asked for another.
  static func run(
    maximumAttempts: Int = 3,
    delayNanoseconds: UInt64 = 20_000_000,
    attempt: @Sendable () async -> HIDFeatureReadAttempt
  ) async -> HIDFeatureReadAttempt {
    for index in 0..<max(0, min(3, maximumAttempts)) {
      guard !Task.isCancelled else { return .stopped }
      if index > 0 {
        do { try await Task.sleep(nanoseconds: delayNanoseconds) } catch { return .stopped }
      }
      guard !Task.isCancelled else { return .stopped }
      switch await attempt() {
      case .accepted: return .accepted
      case .stopped: return .stopped
      case .retry: continue
      }
    }
    return .retry
  }
}
