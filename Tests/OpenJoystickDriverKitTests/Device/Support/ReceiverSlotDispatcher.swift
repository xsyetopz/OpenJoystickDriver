import Foundation

@testable import OpenJoystickDriverKit

/// Records which controllers received input dispatches and which were stopped.
final class ReceiverSlotDispatcher: OutputDispatcher, ControllerLifecycleListener,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recordedDispatches: [LogicalControllerID: [ControllerState]] = [:]
  private var recordedStops: [LogicalControllerID] = []
  private var recordedActivations: [LogicalControllerID] = []

  var suppressOutput = false
  var dispatches: [LogicalControllerID: [ControllerState]] { lock.withLock { recordedDispatches } }
  var stops: [LogicalControllerID] { lock.withLock { recordedStops } }
  var activations: [LogicalControllerID] { lock.withLock { recordedActivations } }

  func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) { lock.withLock { recordedDispatches[identifier, default: []].append(event.state) } }

  func activateOutput(for identifier: LogicalControllerID) {
    lock.withLock { recordedActivations.append(identifier) }
  }

  func controllerDidStop(_ identifier: LogicalControllerID) {
    lock.withLock { recordedStops.append(identifier) }
  }
}

/// Cancels the admitting task at its second inventory change, the moment the second slot's
/// pipeline exists, so that slot's post-start check fails the whole admission. Only a task that
/// binds ``counter`` is affected; other tests post the same notification.
enum ReceiverSlotAdmissionCanceller {
  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var posts = 0

    var count: Int { lock.withLock { posts } }

    func increment() -> Int {
      lock.withLock {
        posts += 1
        return posts
      }
    }
  }

  @TaskLocal
  static var counter: Counter?

  /// Counts the status changes `source` announces; pipelines announce from themselves and do not
  /// count.
  static func observe(from source: AnyObject) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: source,
      queue: nil
    ) { _ in
      guard let counter, counter.increment() == 2 else { return }
      withUnsafeCurrentTask { $0?.cancel() }
    }
  }
}
