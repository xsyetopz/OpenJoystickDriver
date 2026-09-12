import Foundation

enum HIDFeatureReadAttempt: Sendable {
  case accepted
  case retry
  case stopped
}

/// Bounded acquisition; each attempt must revalidate the original pipeline lifetime.
enum HIDFeatureReadRetry {
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
