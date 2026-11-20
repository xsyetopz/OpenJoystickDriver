import os

// `Mutex` needs macOS 15, newer than the macOS 13 floor. `OSAllocatedUnfairLock` takes about
// half the time of `NSLock` per uncontended call. `withLockUnchecked` keeps the body
// non-`@Sendable`; the body runs only while the lock is held, so the state never escapes it.
/// Mutable state that is only reachable through a lock.
///
/// Use it for plain state that several threads read and write. Do not run I/O or callbacks
/// inside `withLock`; copy what you need out of the closure and act on it after the lock is
/// released.
package final class Locked<Value: Sendable>: Sendable {
  /// The lock and the value it guards.
  private let lock: OSAllocatedUnfairLock<Value>

  /// Creates the guard with the initial `value`.
  package init(_ value: Value) { lock = OSAllocatedUnfairLock(initialState: value) }

  /// Runs `body` with exclusive access to the guarded value.
  package func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try lock.withLockUnchecked(body)
  }
}
