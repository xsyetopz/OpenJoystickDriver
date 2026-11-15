import OpenJoystickDriverKit
import SwifterKit

/// Matches asynchronous driver completions, including completions preceding enqueue responses.
/// Native interrupt timeouts stay disabled without blocking a DriverKit work queue.
actor USBDriverKitPendingTransfers {
  /// A caller waiting for its native completion and its optional host deadline.
  private struct Waiter {
    /// Receives one completion or the connection's terminal error.
    let continuation: CheckedContinuation<USBPipeIOCompletion, any Error>
    /// Runs the host-side timeout handling if this request does not complete in time.
    let deadline: Task<Void, Never>?
    /// Aborts the native pipe before reporting an idle deadline to its caller.
    let onTimeout: (@Sendable () async throws -> Void)?
  }

  /// Releases the user-client connection and its outstanding native requests.
  private let closeRuntime: @Sendable () async -> Void
  /// Shared by concurrent close callers so each waits for the same shutdown.
  private var closingTask: Task<Void, Never>?
  /// Callers registered by the native request identifier.
  private var waiters: [UInt32: Waiter] = [:]
  /// Completions delivered before their enqueue commands return identifiers.
  private var early: [UInt32: USBPipeIOCompletion] = [:]
  /// Callers whose native pipe abort must finish before another request may start.
  private var expiring: Set<UInt32> = []
  /// Commands whose enqueue responses have not yet been registered or rejected.
  private var submissions = 0
  /// Whether further requests must be rejected.
  private(set) var isClosed = false

  /// The number of callers currently waiting for native completions.
  var waitingCount: Int { waiters.count }

  /// Creates a completion registry whose terminal failures release the runtime.
  init(closeRuntime: @escaping @Sendable () async -> Void) {
    self.closeRuntime = closeRuntime
  }

  /// Rejects operations after cancellation, a deadline, or explicit close.
  func checkOpen() throws {
    guard !isClosed else { throw USBTransportError.disconnected }
  }

  /// Starts retaining early completions before an enqueue command can run.
  func beginSubmission() throws {
    try checkOpen()
    submissions += 1
  }

  /// Balances an enqueue that failed without returning a native request identifier.
  func submissionFailed() {
    submissions -= 1
    if submissions == 0 { early.removeAll() }
  }

  /// Delivers a completion to its caller, or retains it while an enqueue is in flight.
  func receive(_ completion: USBPipeIOCompletion) {
    guard !isClosed else { return }
    guard !expiring.contains(completion.requestID) else { return }
    if let waiter = waiters.removeValue(forKey: completion.requestID) {
      waiter.deadline?.cancel()
      waiter.continuation.resume(with: result(completion))
    } else if submissions > 0 {
      early[completion.requestID] = completion
    }
  }

  /// Registers an enqueue response and waits for its completion with a host-side deadline.
  func wait(
    requestID: UInt32,
    timeout: UInt32,
    onTimeout: (@Sendable () async throws -> Void)? = nil
  ) async throws -> USBPipeIOCompletion {
    submissions -= 1
    let completion = early.removeValue(forKey: requestID)
    if submissions == 0 { early.removeAll() }
    try checkOpen()
    if let completion { return try result(completion).get() }
    return try await withCheckedThrowingContinuation { continuation in
      let deadline: Task<Void, Never>? =
        timeout == 0
        ? nil
        : Task {
          do { try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000) } catch { return }
          await self.expire(requestID: requestID)
        }
      waiters[requestID] = Waiter(
        continuation: continuation,
        deadline: deadline,
        onTimeout: onTimeout
      )
    }
  }

  /// A completed request's cancelled deadline must never close a subsequent request.
  private func expire(requestID: UInt32) async {
    guard let waiter = waiters[requestID], !Task.isCancelled else { return }
    guard let abort = waiter.onTimeout else {
      await close(error: .timeout)
      return
    }
    expiring.insert(requestID)
    do {
      try await abort()
    } catch {
      await close(error: USBDriverKitTransportProvider.transportError(error))
      return
    }
    expiring.remove(requestID)
    guard let expired = waiters.removeValue(forKey: requestID) else { return }
    expired.continuation.resume(throwing: USBTransportError.timeout)
  }

  /// Wakes every waiting caller and releases the runtime exactly once.
  func close(error: USBTransportError) async {
    guard !isClosed else {
      await closingTask?.value
      return
    }
    isClosed = true
    let closeRuntime = closeRuntime
    let closingTask = Task { await closeRuntime() }
    self.closingTask = closingTask
    let pending = waiters.values
    waiters.removeAll()
    early.removeAll()
    expiring.removeAll()
    for waiter in pending {
      waiter.deadline?.cancel()
      waiter.continuation.resume(throwing: error)
    }
    await closingTask.value
  }

  /// Preserves the native completion's status through the existing error mapping.
  private func result(
    _ completion: USBPipeIOCompletion
  )
    -> Result<USBPipeIOCompletion, USBTransportError>
  {
    guard completion.succeeded else {
      return .failure(
        USBDriverKitTransportProvider.transportError(
          DriverKitError(kind: .ioReturn(completion.status), operation: "USB async completion")
        )
      )
    }
    return .success(completion)
  }
}
