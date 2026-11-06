import Foundation

/// The outcome of one operation on a controller interface's output queue.
enum PhysicalOutputQueueOutcome<Value: Sendable>: Sendable {
  /// The operation ran and returned its value.
  case completed(Value)
  /// `cancelAll()` ran after the operation was queued and before it started, so it did nothing.
  case cancelled
}

extension PhysicalOutputQueueOutcome: Equatable where Value: Equatable {}

/// Proof that code runs inside an operation of a controller interface's output queue.
///
/// Only the queue in this file can create one, so the non-enqueuing `perform*` executor bodies that
/// require it run only inside an operation and never enqueue another one.
struct PhysicalOutputQueueOperation: Sendable {
  /// A private stored property, so that no code outside this file can create a proof.
  private let issuedByQueue: Void
}

extension PhysicalOutputQueueOperation {
  /// Creates a proof; only the queue in this file calls it.
  fileprivate init() { issuedByQueue = () }
}

/// Serializes one controller interface's output: each operation (a user command's encode and its
/// whole plan, one lifecycle write list, or one startup feature read) runs alone, in submission
/// order.
actor PhysicalHIDOutputSerialQueue {
  /// The queue and the sequence of the operation that runs in the current task.
  private struct RunningOperation: Sendable {
    /// The queue that runs the operation.
    let queue: ObjectIdentifier
    /// The sequence of the operation in that queue.
    let sequence: UInt64
  }

  /// The priority of the queue's own tasks, whatever the caller's priority.
  ///
  /// Every operation and tail task runs at this priority, so an operation never waits on a
  /// lower-priority job.
  static let taskPriority = TaskPriority.userInitiated

  /// The operation that runs in the current task; nil outside one.
  @TaskLocal
  private static var runningOperation: RunningOperation?

  /// The last queued operation, which the next one waits for; nil when the queue is idle.
  private var tail: Task<Void, Never>?
  /// The sequence of the latest queued operation.
  private var sequence: UInt64 = 0
  /// The sequence of the operation that runs; nil when none runs.
  private var runningSequence: UInt64?
  /// Operations submitted and not yet returned, including the running one.
  private(set) var submittedOperationCount = 0
  /// Guards ``cancellationEpoch``.
  private let cancellationLock = NSLock()
  /// Counts the calls of ``cancelAll()``; an operation queued under an older count does nothing.
  nonisolated(unsafe) private var cancellationEpoch: UInt64 = 0

  /// A queue whose first operation waits until `predecessor` has drained, so a reconnected
  /// interface's output stays serialized behind a removed queue's running operation.
  init(after predecessor: PhysicalHIDOutputSerialQueue? = nil) {
    tail = predecessor.map { predecessor in
      Task(priority: Self.taskPriority) { await predecessor.drain() }
    }
  }

  /// Queues `operation`. `nonisolated(nonsending)` runs this on the caller's executor, so the
  /// cancellation epoch is read when the caller calls, before the hop onto the queue: a
  /// `cancelAll()` the caller's actor runs after this call cancels the operation.
  nonisolated(nonsending) func perform<Value: Sendable>(
    _ operation: @escaping @Sendable (PhysicalOutputQueueOperation) async -> Value
  ) async -> PhysicalOutputQueueOutcome<Value> {
    await enqueue(operation, queuedAt: currentCancellationEpoch())
  }

  /// Queues `operation` behind its predecessor and waits for its outcome.
  ///
  /// An operation that enqueues on its own queue fails an assertion and gets
  /// ``PhysicalOutputQueueOutcome/cancelled``.
  private func enqueue<Value: Sendable>(
    _ operation: @escaping @Sendable (PhysicalOutputQueueOperation) async -> Value,
    queuedAt epoch: UInt64
  ) async -> PhysicalOutputQueueOutcome<Value> {
    // An operation that enqueues on its own queue would wait for itself forever.
    if let running = Self.runningOperation, running.queue == ObjectIdentifier(self),
      running.sequence == runningSequence
    {
      assertionFailure("An output queue operation enqueued on its own queue")
      return .cancelled
    }
    let previous = tail
    submittedOperationCount += 1
    defer { submittedOperationCount -= 1 }
    sequence &+= 1
    let current = sequence
    let task = Task<PhysicalOutputQueueOutcome<Value>, Never>(priority: Self.taskPriority) {
      // A cancelled operation still waits for its predecessor, so the operations queued after it
      // keep running one at a time.
      if let previous { await previous.value }
      guard self.begin(current, queuedAt: epoch) else { return .cancelled }
      let value = await Self.$runningOperation.withValue(
        RunningOperation(queue: ObjectIdentifier(self), sequence: current)
      ) { await operation(PhysicalOutputQueueOperation()) }
      self.finish(current)
      return .completed(value)
    }
    tail = Task(priority: Self.taskPriority) { _ = await task.value }
    let outcome = await task.value
    if sequence == current { tail = nil }
    return outcome
  }

  /// Returns once every operation queued so far, and any queued while waiting, has returned.
  func drain() async {
    while let current = tail {
      await current.value
      if tail == current { return }
    }
  }

  /// Cancels every queued operation that has not started; the running one completes.
  ///
  /// Operations queued afterwards, such as neutralization, run normally.
  nonisolated func cancelAll() { cancellationLock.withLock { cancellationEpoch &+= 1 } }

  /// The current value of the cancellation epoch.
  nonisolated private func currentCancellationEpoch() -> UInt64 {
    cancellationLock.withLock { cancellationEpoch }
  }

  /// Starts the operation `operation` unless ``cancelAll()`` ran after it was queued under `epoch`.
  ///
  /// - Returns: Whether the operation may run.
  private func begin(_ operation: UInt64, queuedAt epoch: UInt64) -> Bool {
    guard currentCancellationEpoch() == epoch else { return false }
    runningSequence = operation
    return true
  }

  /// Ends the operation `operation`.
  private func finish(_ operation: UInt64) {
    if runningSequence == operation { runningSequence = nil }
  }
}
