package import Foundation

/// Runs synchronous work that may block (socket I/O, native device creation) off the Swift
/// concurrency cooperative pool.
package enum BlockingWork {
  /// Runs `work` on a new serial dispatch queue and resumes the caller once with its outcome.
  ///
  /// Each call gets its own queue, so one blocked operation never delays another.
  package static func run<Value: Sendable>(
    label: String,
    _ work: @escaping @Sendable () throws -> Value
  ) async throws -> Value { try await run(on: DispatchQueue(label: label), work) }

  /// Runs `work` on `queue` and resumes the caller once with its outcome.
  ///
  /// Use a long-lived serial queue for work that is already serialized and runs often, such as
  /// per-report device calls, so each call does not create a queue.
  package static func run<Value: Sendable>(
    on queue: DispatchQueue,
    _ work: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { continuation.resume(with: Result(catching: work)) }
    }
  }

  /// Runs `work` once on its own serial dispatch queue, without waiting for it.
  ///
  /// A concurrent queue gives blocked work only a limited pool of threads, and a thread that
  /// blocks on a socket for seconds lets queued work wait behind it; a serial queue is started on
  /// a thread of its own at once.
  package static func detach(label: String, _ work: @escaping @Sendable () -> Void) {
    DispatchQueue(label: label).async(execute: work)
  }

  /// Runs `work` on a thread of its own that takes no thread of Grand Central Dispatch's pool,
  /// without waiting for it.
  ///
  /// Use it for loops that block for as long as the process lives, such as an accept loop, and
  /// for waits that must fire on time while the pool is saturated.
  package static func detachThread(name: String, _ work: @escaping @Sendable () -> Void) {
    let thread = Thread(block: work)
    thread.name = name
    thread.start()
  }
}
