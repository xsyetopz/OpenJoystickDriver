import Foundation

/// One bounded, ordered stream for event reports and host-protocol replies.
/// Closing revokes new submissions and detaches the backend before the active native send drains.
final class UserSpaceReportSender: Sendable {
  enum Failure: Error, Equatable, LocalizedError, Sendable {
    case queueOverflow
    case sendTimedOut

    var errorDescription: String? {
      switch self {
      case .queueOverflow: "Virtual controller publication queue overflowed."
      case .sendTimedOut: "Virtual controller publication timed out."
      }
    }
  }

  private static let queueCapacity = 64
  /// Matches the virtual output transition deadline used to retire native virtual devices.
  static let defaultNativeSendDeadlineNanoseconds: UInt64 = 2_000_000_000

  final class SubmissionReceipt: Sendable {
    private struct State: Sendable {
      var result: Result<Void, any Error>?
      var waiters: [CheckedContinuation<Void, any Error>] = []
    }

    private let state = Locked(State())

    func finish(_ result: Result<Void, any Error>) {
      let waiters = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
        guard state.result == nil else { return [] }
        state.result = result
        defer { state.waiters.removeAll() }
        return state.waiters
      }
      for waiter in waiters { waiter.resume(with: result) }
    }

    func value() async throws {
      try await withCheckedThrowingContinuation { continuation in
        let result = state.withLock { state -> Result<Void, any Error>? in
          if let result = state.result { return result }
          state.waiters.append(continuation)
          return nil
        }
        if let result { continuation.resume(with: result) }
      }
    }
  }

  /// Races one native send against its deadline and resumes the waiting publisher exactly once.
  ///
  /// The send and the deadline run in unstructured tasks, not in a task group, because a group
  /// awaits every child: a native send that ignores cancellation would hold the worker past the
  /// deadline. Cancelling the waiting publisher (closing) must also not cut the deadline short,
  /// so the send can still drain until then.
  private final class NativeSendOperation: Sendable {
    private struct State: Sendable {
      var completed = false
      var cancellationRequested = false
      var sendTask: Task<Void, Never>?
      var deadlineTask: Task<Void, Never>?
      var continuation: CheckedContinuation<Void, any Error>?
    }

    private let state = Locked(State())

    func start(
      report: [UInt8],
      backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend,
      deadlineNanoseconds: UInt64,
      continuation: CheckedContinuation<Void, any Error>
    ) {
      state.withLock { $0.continuation = continuation }
      let send = Task.detached { [weak self] in
        do {
          try await backend.send(report)
          self?.finish(.success(()))
        } catch { self?.finish(.failure(error)) }
      }
      let deadline = Task.detached { [weak self] in
        do {
          try await Task.sleep(nanoseconds: deadlineNanoseconds)
          if self?.isCancellationRequested() == true {
            self?.finish(.failure(CancellationError()))
          } else {
            backend.close()
            self?.finish(.failure(Failure.sendTimedOut))
          }
        } catch {
          // Cancellation only stops the deadline.
        }
      }
      let didComplete = state.withLock { state -> Bool in
        state.sendTask = send
        state.deadlineTask = deadline
        return state.completed
      }
      if didComplete {
        send.cancel()
        deadline.cancel()
      }
    }

    func cancel() {
      let sendTask = state.withLock { state -> Task<Void, Never>? in
        state.cancellationRequested = true
        return state.sendTask
      }
      sendTask?.cancel()
    }

    private func isCancellationRequested() -> Bool { state.withLock { $0.cancellationRequested } }

    private func finish(_ result: Result<Void, any Error>) {
      let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
        guard !state.completed else { return nil }
        state.completed = true
        state.deadlineTask?.cancel()
        defer { state.continuation = nil }
        return state.continuation
      }
      continuation?.resume(with: result)
    }
  }

  private struct Submission: Sendable {
    let completion: SubmissionReceipt
    let whileActive: @Sendable () -> Bool
    let requireActive: Bool
    let reports: @Sendable () throws -> [[UInt8]]
  }

  private struct State: Sendable {
    var backend: (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?
    var worker: Task<Void, Never>?
    var pending: [ObjectIdentifier: SubmissionReceipt] = [:]
    var active: SubmissionReceipt?
    var closeTask: Task<Void, Never>?
    var closed = false
  }

  private let state = Locked(State())
  private let continuation: AsyncStream<Submission>.Continuation
  private let nativeSendDeadlineNanoseconds: UInt64

  init(nativeSendDeadlineNanoseconds: UInt64 = defaultNativeSendDeadlineNanoseconds) {
    self.nativeSendDeadlineNanoseconds = nativeSendDeadlineNanoseconds
    let (stream, continuation) = AsyncStream.makeStream(
      of: Submission.self,
      bufferingPolicy: .bufferingOldest(Self.queueCapacity)
    )
    self.continuation = continuation
    let worker = Task { [weak self] in
      for await submission in stream {
        guard let self else {
          submission.completion.finish(.failure(CancellationError()))
          continue
        }
        await self.publish(submission)
      }
    }
    state.withLock { $0.worker = worker }
  }

  deinit { _ = beginClose() }

  func attach(_ backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend) {
    let rejected = state.withLock { state in
      guard !state.closed, state.backend == nil else { return true }
      state.backend = backend
      return false
    }
    if rejected { backend.close() }
  }

  /// Builds reports in the retained worker only after preceding publication completes.
  ///
  /// Enqueueing stays synchronous: IOKit's set-report callback acknowledges ordered enqueueing
  /// and cannot await. Await `SubmissionReceipt.value()` for the publication outcome.
  func submit(
    whileActive: @escaping @Sendable () -> Bool = { true },
    requireActive: Bool = false,
    _ reports: @escaping @Sendable () throws -> [[UInt8]]
  ) -> SubmissionReceipt {
    let completion = SubmissionReceipt()
    let submission = Submission(
      completion: completion,
      whileActive: whileActive,
      requireActive: requireActive,
      reports: reports
    )
    let result = state.withLock { state -> Result<Void, any Error>? in
      guard !state.closed else { return .failure(CancellationError()) }
      let key = ObjectIdentifier(completion)
      state.pending[key] = completion
      switch continuation.yield(submission) {
      case .enqueued: return nil
      case .dropped:
        state.pending.removeValue(forKey: key)
        return .failure(Failure.queueOverflow)
      case .terminated:
        state.pending.removeValue(forKey: key)
        return .failure(CancellationError())
      @unknown default:
        state.pending.removeValue(forKey: key)
        return .failure(CancellationError())
      }
    }
    if let result { completion.finish(result) }
    return completion
  }

  private func publish(_ submission: Submission) async {
    state.withLock { $0.active = submission.completion }
    defer {
      state.withLock { state in
        state.pending.removeValue(forKey: ObjectIdentifier(submission.completion))
        if state.active === submission.completion { state.active = nil }
      }
    }
    do {
      try Task.checkCancellation()
      let backend = try state.withLock { state in
        guard !state.closed, let backend = state.backend else { throw CancellationError() }
        return backend
      }
      for report in try submission.reports() {
        guard !state.withLock({ $0.closed }) else { throw CancellationError() }
        guard submission.whileActive() else {
          if submission.requireActive { throw CancellationError() }
          submission.completion.finish(.success(()))
          return
        }
        try await send(report, to: backend)
      }
      submission.completion.finish(.success(()))
    } catch { submission.completion.finish(.failure(error)) }
  }

  private func send(
    _ report: [UInt8],
    to backend: any UserSpaceOutputDispatcher.VirtualDeviceBackend
  ) async throws {
    let operation = NativeSendOperation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        operation.start(
          report: report,
          backend: backend,
          deadlineNanoseconds: nativeSendDeadlineNanoseconds,
          continuation: continuation
        )
      }
    } onCancel: {
      operation.cancel()
    }
  }

  @discardableResult
  func beginClose() -> Task<Void, Never> {
    let result = state.withLock {
      state -> (
        Task<Void, Never>, (any UserSpaceOutputDispatcher.VirtualDeviceBackend)?,
        [SubmissionReceipt]
      ) in
      if let closeTask = state.closeTask { return (closeTask, nil, []) }
      state.closed = true
      continuation.finish()
      let backend = state.backend
      state.backend = nil
      let activeIdentifier = state.active.map { ObjectIdentifier($0) }
      let cancellations = state.pending.compactMap { key, completion in
        key == activeIdentifier ? nil : completion
      }
      state.pending.removeAll()
      state.worker?.cancel()
      let worker = state.worker
      let task = Task {
        // The backend is closed right after this task starts; wait until the native device is
        // gone, so a replacement is never published beside it.
        await backend?.waitUntilClosed()
        if let worker { await worker.value }
      }
      state.closeTask = task
      return (task, backend, cancellations)
    }
    result.1?.close()
    result.2.forEach { $0.finish(.failure(CancellationError())) }
    return result.0
  }
}
