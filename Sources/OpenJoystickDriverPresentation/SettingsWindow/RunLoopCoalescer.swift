import Foundation

/// Runs an action once for any number of `schedule()` calls made before the deferred turn runs.
@MainActor
final class RunLoopCoalescer {
  /// Runs when the deferred turn comes.
  private let action: @MainActor () -> Void
  /// Runs its work on a later turn.
  private let deferring: (@escaping @MainActor () -> Void) -> Void
  /// Whether a deferred turn is waiting to run the action.
  private var isScheduled = false

  /// Creates the coalescer.
  ///
  /// - Parameters:
  ///   - deferring: runs its work on a later turn of the main run loop.
  ///   - action: what runs once per turn.
  init(
    deferring: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
      Task { @MainActor in work() }
    },
    action: @escaping @MainActor () -> Void
  ) {
    self.deferring = deferring
    self.action = action
  }

  /// Asks for the action to run on a later turn; further calls before that turn change nothing.
  func schedule() {
    guard !isScheduled else { return }
    isScheduled = true
    deferring { [self] in
      isScheduled = false
      action()
    }
  }
}
