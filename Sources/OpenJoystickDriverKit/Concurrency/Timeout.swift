import Foundation

/// Awaits `operation` until it completes or `seconds` elapse, returning nil on timeout or error.
///
/// The operation runs in its own task so a call that never replies (for example an invalidated
/// service connection or a hung device) cannot hold the command past its deadline; it is cancelled
/// once the deadline passes or the caller is cancelled.
package func withTimeout<T: Sendable>(
  seconds: Double,
  _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
  let outcomes = AsyncStream<T?>(bufferingPolicy: .bufferingOldest(1)) { continuation in
    let work = Task {
      continuation.yield(try? await operation())
      continuation.finish()
    }
    let deadline = Task {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      continuation.yield(nil)
      continuation.finish()
    }
    continuation.onTermination = { _ in
      work.cancel()
      deadline.cancel()
    }
  }
  for await outcome in outcomes { return outcome }
  return nil
}
