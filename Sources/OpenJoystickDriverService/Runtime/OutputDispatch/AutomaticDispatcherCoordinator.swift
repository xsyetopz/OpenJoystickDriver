import Foundation
import OpenJoystickDriverKit

/// Owns installation requests until activation, retirement, and suppression have completed.
actor AutomaticDispatcherCoordinator {

  /// The publication state of each controller.
  var entries: [LogicalControllerID: Entry] = [:]
  /// Whether ``close()`` was called.
  var closed = false
  /// Whether ``close()`` has finished retiring every backend.
  var closeFinished = false
  /// The callers of ``close()`` that wait for it to finish.
  var closeWaiters: [CheckedContinuation<Void, Never>] = []
  /// Whether remapping output is suppressed on the installed backends.
  var remappingSuppressed = false
  /// Whether all virtual output is suppressed.
  var suppressed = false
  /// Advances on each suppression change, so a change that arrives mid-update is applied again.
  var suppressionRevision: UInt64 = 0
  /// The wait before a failed publication is retried, in nanoseconds.
  let recoveryDelayNanoseconds: UInt64

  /// Creates a coordinator that retries a failed publication after `recoveryDelayNanoseconds`.
  init(recoveryDelayNanoseconds: UInt64 = 5_000_000_000) {
    self.recoveryDelayNanoseconds = recoveryDelayNanoseconds
  }
}
