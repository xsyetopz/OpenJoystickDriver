import Foundation
import OpenJoystickDriverKit

/// The failure of a bounded step of a virtual output transition.
enum VirtualOutputTransitionError: Error, Sendable {
  /// A stage of the transition did not finish in time.
  case stageTimedOut
  /// The at-rest feedback writes did not finish in time.
  case feedbackTimedOut
  /// Closing the candidate backend did not finish in time.
  case candidateCloseTimedOut
  /// Activating the backend did not finish in time.
  case activationTimedOut
}

/// Runs `operation` and returns its value, or throws `error` when `timeout` nanoseconds pass first.
///
/// The operation keeps running after a timeout; `onLateSuccess` receives its value then.
///
/// - Throws: `error` on timeout, `CancellationError` when the caller is cancelled first, or
///   the error of `operation`.
func withVirtualOutputTimeout<Value: Sendable>(
  _ timeout: UInt64,
  clock: VirtualOutputTransitionClock,
  error: VirtualOutputTransitionError,
  operation: @escaping @Sendable () async throws -> Value,
  onLateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
) async throws -> Value {
  guard timeout > 0 else { throw error }

  let stream = AsyncThrowingStream<Value, any Error> { continuation in
    // Detached: on timeout the caller returns while the operation runs on to `onLateSuccess`.
    let operationTask = Task.detached {
      do {
        let result = try await operation()
        switch continuation.yield(result) {
        case .enqueued: continuation.finish()
        case .dropped, .terminated:
          await onLateSuccess(result)
          continuation.finish()
        @unknown default: continuation.finish()
        }
      } catch { continuation.finish(throwing: error) }
    }
    // Detached: a child task would make the caller wait for an operation that ignores cancellation.
    let timerTask = Task.detached {
      do {
        try await clock.sleep(timeout)
        continuation.finish(throwing: error)
      } catch {
        // Cancellation only stops the timer.
      }
    }
    continuation.onTermination = { _ in
      operationTask.cancel()
      timerTask.cancel()
    }
  }
  var iterator = stream.makeAsyncIterator()
  guard let result = try await iterator.next() else { throw CancellationError() }
  return result
}

/// A stop flag that the queued operations of a coordinator check.
final class VirtualOutputTransitionCancellation: Sendable {
  /// Whether the coordinator was stopped.
  private let stopped = Locked(false)

  /// Whether ``stop()`` was called.
  var isStopped: Bool { stopped.withLock { $0 } }
  /// Sets the flag.
  func stop() { stopped.withLock { $0 = true } }
}

/// Runs the operations of a virtual output transition one at a time, in the order they were queued.
actor VirtualOutputTransitionCoordinator {
  /// The last queued operation, which the next one waits for.
  private var tail: Task<Void, Never>?
  /// The flag that stops queued operations from starting.
  private let cancellation = VirtualOutputTransitionCancellation()
  /// Operations accepted since creation, counted when queued, before they start.
  private(set) var queuedOperationCount = 0

  /// Runs `operation` after every earlier operation; false when the coordinator stops first.
  func enqueue(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
    await enqueueResult(operation) ?? false
  }

  /// Runs `operation` after every earlier operation; nil when the coordinator stops first.
  func enqueueResult<Value: Sendable>(
    _ operation: @escaping @Sendable () async -> Value
  ) async -> Value? {
    guard !cancellation.isStopped else { return nil }
    queuedOperationCount += 1
    let previous = tail
    let gate = self.cancellation
    let next = Task<Value?, Never> {
      await previous?.value
      guard !Task.isCancelled, !gate.isStopped else { return nil }
      return await operation()
    }
    tail = Task {
      await withTaskCancellationHandler {
        _ = await next.value
      } onCancel: {
        next.cancel()
      }
    }
    return await next.value
  }

  /// Stops the queue: cancels the queued operations and refuses further ones.
  func stop() {
    cancellation.stop()
    tail?.cancel()
    tail = nil
  }
}

/// Closes a virtual output backend once, however many callers ask.
final class VirtualOutputBackendCloseSlot: Sendable {
  /// The backend to close.
  let backend: any VirtualOutputDispatching
  /// The close task, created by the first caller.
  private let closeTask = Locked<Task<Void, Never>?>(nil)

  /// Creates a slot for `backend`.
  init(_ backend: any VirtualOutputDispatching) { self.backend = backend }

  /// Closes the backend and returns true, or returns false when `timeout` nanoseconds pass first.
  func close(timeout: UInt64, clock: VirtualOutputTransitionClock) async -> Bool {
    let closing = self.backend
    let task = closeTask.withLock { closeTask -> Task<Void, Never> in
      if let closeTask { return closeTask }
      // Detached: the close outlives a timed-out caller, and later callers await the same task.
      let task = Task.detached { await closing.close() }
      closeTask = task
      return task
    }
    do {
      try await withVirtualOutputTimeout(timeout, clock: clock, error: .candidateCloseTimedOut) {
        await task.value
      }
      return true
    } catch { return false }
  }
}
