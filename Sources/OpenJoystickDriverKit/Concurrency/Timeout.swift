import Foundation

/// Thrown by `withTimeout` when the deadline passes before the operation finishes.
package struct TimeoutError: Error, Equatable {
  /// The deadline that passed, in seconds.
  package let seconds: Double
}

/// Awaits `operation` until it completes or `seconds` elapse.
///
/// Returns the operation's value, rethrows the operation's own error, and throws `TimeoutError`
/// only when the deadline passes first.
///
/// The operation runs in its own task so a call that never replies (for example an invalidated
/// service connection or a hung device) cannot hold the command past its deadline; it is cancelled
/// once the deadline passes or the caller is cancelled.
package func withTimeout<T: Sendable>(
  seconds: Double,
  _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let outcomes = AsyncStream<Result<T, any Error>>(bufferingPolicy: .bufferingOldest(1)) {
    continuation in
    let work = Task {
      do { continuation.yield(.success(try await operation())) } catch {
        continuation.yield(.failure(error))
      }
      continuation.finish()
    }
    // The deadline runs on a timer thread, not the cooperative pool, so a starved pool cannot
    // delay it.
    let cancelDeadline = DeadlineTimer.dispatch.schedule(UInt64(seconds * 1_000_000_000)) {
      continuation.yield(.failure(TimeoutError(seconds: seconds)))
      continuation.finish()
    }
    continuation.onTermination = { _ in
      work.cancel()
      cancelDeadline()
    }
  }
  for await outcome in outcomes { return try outcome.get() }
  throw CancellationError()
}
