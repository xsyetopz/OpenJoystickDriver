import Foundation

/// Runs a synchronous HID read off the caller's actor and gives up after a deadline, so a device
/// that never answers cannot hold up the caller.
///
/// A synchronous host read has no timeout of its own, and a read that timed out keeps its thread
/// until the system call returns. A device with such a read outstanding is not read again: the next
/// read fails at once with `PhysicalHIDFailure.busy`, so a silent device cannot pile up blocked
/// threads.
package final class BoundedHIDRead: Sendable {
  /// The keys of the devices with a read that has not returned.
  private let outstanding = Locked<Set<UUID>>([])
  /// Schedules the deadline of a read.
  private let scheduleDeadline: DeadlineScheduler

  /// Runs an action once the given seconds have passed.
  package typealias DeadlineScheduler =
    @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

  /// `scheduleDeadline` runs its action once `timeout` seconds have passed; tests replace it to
  /// observe the deadline a read is given.
  package init(scheduleDeadline: @escaping DeadlineScheduler = BoundedHIDRead.dispatchAfter) {
    self.scheduleDeadline = scheduleDeadline
  }

  /// Runs `action` on a global queue after `timeout` seconds.
  @Sendable
  private static func dispatchAfter(
    _ timeout: TimeInterval,
    _ action: @escaping @Sendable () -> Void
  ) {
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: action)
  }

  /// The outcome of `read` for the device `key`, a `PhysicalHIDFailure.timedOut` failure when it
  /// has not returned within `timeout` seconds, or a `PhysicalHIDFailure.busy` failure, without
  /// calling `read`, while an earlier read of `key` has not returned.
  package func run(
    key: UUID,
    timeout: TimeInterval,
    read: @escaping @Sendable () -> PhysicalHIDReportResult<Data>
  ) async -> PhysicalHIDReportResult<Data> {
    let admitted = outstanding.withLock { $0.insert(key).inserted }
    guard admitted else { return .failed(.busy) }
    return await withCheckedContinuation { continuation in
      let pending = Locked<CheckedContinuation<PhysicalHIDReportResult<Data>, Never>?>(
        continuation
      )
      @Sendable
      func finish(_ result: PhysicalHIDReportResult<Data>) {
        let waiting = pending.withLock {
          current -> CheckedContinuation<
            PhysicalHIDReportResult<Data>, Never
          >? in
          defer { current = nil }
          return current
        }
        waiting?.resume(returning: result)
      }
      DispatchQueue(label: "OpenJoystickDriver.HIDFeatureProbe").async { [outstanding] in
        let result = read()
        _ = outstanding.withLock { $0.remove(key) }
        finish(result)
      }
      scheduleDeadline(timeout) { finish(.failed(.timedOut)) }
    }
  }
}
