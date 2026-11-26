import Foundation

/// Admits a bounded number of in-process `ojd` runs at a time, first come first served.
///
/// Parsing a command line and formatting a usage error are CPU-bound and run on the shared
/// cooperative pool, whose width is the processor count. With hundreds of test cases started at
/// once, those runs fill the pool, and the in-process server's reply task waits behind them until
/// the request deadline passes. Admitting half the pool width keeps threads free for replies.
///
/// A test that runs many commands in sequence holds one permit for the whole sequence, so it
/// does not queue again behind the rest of the suite for each command.
actor CLIRunGate {
  static let shared = CLIRunGate(permits: max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

  /// Whether the current task already holds a permit.
  @TaskLocal
  private static var admitted = false

  private var available: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(permits: Int) {
    available = permits
  }

  /// Runs `body` once a permit is free, and frees the permit when `body` returns.
  ///
  /// Within `body`, nested calls run at once on the same permit.
  nonisolated func run<T: Sendable>(_ body: () async -> T) async -> T {
    if Self.admitted { return await body() }
    await acquire()
    let result = await Self.$admitted.withValue(true) { await body() }
    await release()
    return result
  }

  /// Runs a throwing `body` on one permit, as ``run(_:)`` does.
  nonisolated func runThrowing(_ body: () async throws -> Void) async throws {
    let failure: (any Error)? = await run {
      do {
        try await body()
        return nil
      } catch { return error }
    }
    if let failure { throw failure }
  }

  private func acquire() async {
    guard available == 0 else {
      available -= 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  private func release() {
    if waiters.isEmpty {
      available += 1
    } else {
      waiters.removeFirst().resume()
    }
  }
}
