import Foundation
import OpenJoystickDriverKit

/// Owns installation requests until activation, retirement, and pausing have completed.
actor AutomaticDispatcherCoordinator {

  /// The publication state of each controller.
  var entries: [LogicalControllerID: Entry] = [:] {
    didSet { revision &+= 1 }
  }
  /// Advances on each change to `entries` or `suppressed`, so a delivery that sees the revision
  /// it last synchronized skips rebuilding the publication snapshot.
  ///
  /// A steady delivery writes neither, so the revision holds still while input streams.
  private(set) var revision: UInt64 = 0
  /// Whether ``close()`` was called.
  var closed = false
  /// Whether ``close()`` has finished retiring every backend.
  var closeFinished = false
  /// The callers of ``close()`` that wait for it to finish.
  var closeWaiters: [CheckedContinuation<Void, Never>] = []
  /// Whether remapping output is paused on the installed backends.
  var remappingSuppressed = false
  /// Whether all virtual output is paused.
  var suppressed = false {
    didSet { if suppressed != oldValue { revision &+= 1 } }
  }
  /// Advances on each pause change, so a change that arrives mid-update is applied again.
  var suppressionRevision: UInt64 = 0
  /// The wait before a failed publication is retried, in nanoseconds.
  let recoveryDelayNanoseconds: UInt64

  /// Creates a coordinator that retries a failed publication after `recoveryDelayNanoseconds`.
  init(recoveryDelayNanoseconds: UInt64 = 5_000_000_000) {
    self.recoveryDelayNanoseconds = recoveryDelayNanoseconds
  }
}
