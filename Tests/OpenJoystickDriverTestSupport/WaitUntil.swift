package import Foundation
package import Testing

/// Suspends until `condition` holds.
///
/// The condition is re-evaluated every millisecond with no iteration limit, so passing does not
/// depend on scheduling speed; the deadline, in seconds, only bounds a condition that never becomes
/// true and records it as a failure.
package func waitUntil(
  _ description: String,
  deadline: TimeInterval = 60,
  isolation _: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ condition: () async -> Bool
) async {
  let limit = ProcessInfo.processInfo.systemUptime + deadline
  while !(await condition()) {
    guard ProcessInfo.processInfo.systemUptime < limit, !Task.isCancelled else {
      Issue.record("Condition never held: \(description)", sourceLocation: sourceLocation)
      return
    }
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
}
