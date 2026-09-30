import Foundation

// `@unchecked Sendable` is sound because `value` is private and every access goes through
// `lock`. `Mutex` and `OSAllocatedUnfairLock` need newer systems than the macOS 12 floor.
/// Mutable state that is only reachable through a lock.
///
/// Use it for plain state that several threads read and write. Do not run I/O or callbacks
/// inside `withLock`; copy what you need out of the closure and act on it after the lock is
/// released.
package final class Locked<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  package init(_ value: Value) { self.value = value }

  /// Runs `body` with exclusive access to the guarded value.
  package func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}
