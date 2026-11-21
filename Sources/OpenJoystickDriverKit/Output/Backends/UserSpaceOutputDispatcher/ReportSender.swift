import Foundation

/// One bounded, ordered stream for event reports and host-protocol replies.
///
/// At most `queueCapacity` submissions wait behind the one being sent. When the queue is full, a
/// new submission evicts the oldest waiting frame (newest wins); the evicted frame's receipt fails
/// with ``Failure/superseded``. Every frame carries the complete controller state, so the newest
/// frame still brings the virtual device up to date. A submission that is not a frame, such as a
/// host output report, is never evicted: with no frame left to evict it fails with
/// ``Failure/queueOverflow``, while a frame that finds only such submissions fails with
/// ``Failure/superseded``.
/// Closing revokes new submissions and detaches the backend before the active native send drains.
///
/// Reports are built and sent on the sender's own serial queue, never on the submitter's thread:
/// the host set-report callback submits while it holds its lock.
final class UserSpaceReportSender: Sendable {
  /// Why a submission does not reach the device.
  enum Failure: Error, Equatable, LocalizedError, Sendable {
    /// The queue holds only host replies, and one more arrived.
    case queueOverflow
    /// The native send exceeded its deadline.
    case sendTimedOut
    /// A newer frame took the place of this one in a full queue.
    case superseded

    /// The description of the error for the user.
    var errorDescription: String? {
      switch self {
      case .queueOverflow: "Virtual controller publication queue overflowed."
      case .sendTimedOut: "Virtual controller publication timed out."
      case .superseded: "Virtual controller frame superseded by a newer frame."
      }
    }
  }

  /// Matches the virtual output transition deadline used to retire native virtual devices.
  static let defaultNativeSendDeadlineNanoseconds: UInt64 = 2_000_000_000

  /// The outcome of one submission.
  final class SubmissionReceipt: Sendable {
    /// The result and the tasks that wait for it.
    private struct State: Sendable {
      /// The result; nil until the submission ends.
      var result: Result<Void, any Error>?
      /// The tasks that wait for the result.
      var waiters: [CheckedContinuation<Void, any Error>] = []
    }

    /// The result and its waiters.
    private let state = Locked(State())

    /// Sets the result and resumes every waiter; only the first call counts.
    func finish(_ result: Result<Void, any Error>) {
      let waiters = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
        guard state.result == nil else { return [] }
        state.result = result
        defer { state.waiters.removeAll() }
        return state.waiters
      }
      for waiter in waiters { waiter.resume(with: result) }
    }

    /// Waits for the result.
    ///
    /// - Throws: The error of the submission, such as ``Failure/superseded``.
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

  /// Bounds one native send by the sender's deadline and ends it exactly once.
  ///
  /// The first of the backend's outcome, the deadline and a cancelled close ends the send. The
  /// deadline runs on the sender's watchdog, not in a task, so a native send that blocks or ignores
  /// cancellation cannot hold it past the deadline. A cancelled close does not cut the deadline
  /// short, so the send can still drain until then.
  private final class NativeSendOperation: Sendable {
    /// The progress of the send.
    private struct State: Sendable {
      /// Whether the send ended.
      var completed = false
      /// Whether closing cancelled the send.
      var cancellationRequested = false
      /// Asks the native send to stop.
      var cancelSend: (@Sendable () -> Void)?
      /// The send's number at the watchdog.
      var watch: UInt64?
    }

    /// The progress of the send.
    private let state = Locked(State())
    /// Expires the send at its deadline.
    private let watchdog: ReportSendWatchdog

    /// Creates the operation of one send that `watchdog` bounds.
    init(watchdog: ReportSendWatchdog) { self.watchdog = watchdog }

    /// Starts the deadline; at the deadline it closes `backend` and passes
    /// ``Failure/sendTimedOut``, or a `CancellationError` after ``cancel()``, to `onExpire`.
    func arm(backend: any VirtualDeviceBackend, onExpire: @escaping @Sendable (any Error) -> Void) {
      let watch = watchdog.begin { [weak self] in
        guard let self else { return }
        let error: any Error
        if state.withLock({ $0.cancellationRequested }) {
          error = CancellationError()
        } else {
          backend.close()
          error = Failure.sendTimedOut
        }
        if end() { onExpire(error) }
      }
      let ended = state.withLock { state -> Bool in
        state.watch = watch
        return state.completed
      }
      if ended { watchdog.end(watch) }
    }

    /// Keeps `cancelSend` for ``cancel()``; it runs at once when the send already ended.
    func setCancel(_ cancelSend: @escaping @Sendable () -> Void) {
      let ended = state.withLock { state -> Bool in
        state.cancelSend = cancelSend
        return state.completed
      }
      if ended { cancelSend() }
    }

    /// Asks the native send to stop; the deadline then ends it with a cancellation.
    func cancel() {
      let cancelSend = state.withLock { state -> (@Sendable () -> Void)? in
        state.cancellationRequested = true
        return state.cancelSend
      }
      cancelSend?()
    }

    /// Ends the send; only the first call returns true.
    func end() -> Bool {
      let (first, watch) = state.withLock { state -> (Bool, UInt64?) in
        guard !state.completed else { return (false, nil) }
        state.completed = true
        return (true, state.watch)
      }
      if let watch { watchdog.end(watch) }
      return first
    }
  }

  /// One request for reports.
  private struct Submission: Sendable {
    /// The outcome that the submitter waits for.
    let completion: SubmissionReceipt
    /// Whether a newer frame may take this submission's place in a full queue.
    let isFrame: Bool
    /// Whether the reports still apply.
    let whileActive: @Sendable () -> Bool
    /// Whether a report that does not apply any more fails the submission instead of ending it.
    let requireActive: Bool
    /// Builds the reports to send.
    let reports: @Sendable () throws -> [[UInt8]]
  }

  /// The device that receives the reports, with its blocking send when it has one.
  private struct Destination: Sendable {
    /// The device.
    let backend: any VirtualDeviceBackend
    /// The same device when its native send blocks; the sender calls it on its own queue.
    let blocking: (any BlockingVirtualDeviceBackend)?
  }

  /// Whether a send finished on the sender's queue or continues there from its completion.
  private enum Step {
    /// The send finished with this outcome.
    case finished(Result<Void, any Error>)
    /// The send's completion continues the submission.
    case pending
  }

  /// The state that the lock guards.
  private struct State: Sendable {
    /// The device that receives the reports; nil before ``attach(_:)`` and after closing.
    var destination: Destination?
    /// The outcome of every submission that is waiting or being sent.
    var pending: [ObjectIdentifier: SubmissionReceipt] = [:]
    /// The submissions waiting to be sent, oldest first; never longer than the capacity.
    var queue: [Submission] = []
    /// The submission being sent.
    var active: SubmissionReceipt?
    /// The native send in flight.
    var operation: NativeSendOperation?
    /// Whether the sender's queue runs or has a step scheduled.
    var running = false
    /// Whether the deadline or a cancellation ended a send that the backend has not returned.
    var abandoned = false
    /// The closing tasks that wait for the queue to stop or abandon its send.
    var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    /// The task that closing started.
    var closeTask: Task<Void, Never>?
    /// Whether the sender is closed.
    var closed = false
  }

  /// The state that the lock guards.
  private let state = Locked(State())
  /// Builds and sends the submissions in order, one at a time.
  ///
  /// Each frame costs one wake of this queue and one of the waiting publisher: a backend whose
  /// native send blocks sends on this queue, so no further thread takes part.
  private let chain = DispatchQueue(label: "com.openjoystickdriver.output.sender")
  /// Enforces the deadline of each native send.
  private let watchdog: ReportSendWatchdog
  /// The most submissions that wait behind the one being sent.
  private let queueCapacity: Int

  /// The number of submissions waiting behind the one being sent.
  var queuedCount: Int { state.withLock { $0.queue.count } }

  /// Creates a sender with a queue of `queueCapacity` submissions and a native send deadline of
  /// `nativeSendDeadlineNanoseconds`.
  init(
    nativeSendDeadlineNanoseconds: UInt64 = defaultNativeSendDeadlineNanoseconds,
    queueCapacity: Int = ControllerTuning.defaultFrameQueueCapacity,
    deadlineTimer: DeadlineTimer = .dispatch
  ) {
    // Decoding refuses a capacity outside the range, so another value is a programming error.
    precondition(
      ControllerTuning.frameQueueCapacityRange.contains(queueCapacity),
      "frame queue capacity \(queueCapacity) is outside \(ControllerTuning.frameQueueCapacityRange)"
    )
    self.watchdog = ReportSendWatchdog(
      deadlineNanoseconds: nativeSendDeadlineNanoseconds,
      timer: deadlineTimer
    )
    self.queueCapacity = queueCapacity
  }

  deinit { _ = beginClose() }

  /// Sets the device that receives the reports; a closed sender or a second device is closed at
  /// once.
  func attach(_ backend: any VirtualDeviceBackend) {
    // The blocking send is looked up once here, so no report pays for the dynamic cast.
    let destination = Destination(
      backend: backend,
      blocking: backend as? any BlockingVirtualDeviceBackend
    )
    let rejected = state.withLock { state in
      guard !state.closed, state.destination == nil else { return true }
      state.destination = destination
      return false
    }
    if rejected { backend.close() }
  }

  /// Builds reports on the sender's queue only after preceding publication completes.
  ///
  /// Enqueueing stays synchronous: the native set-report callback acknowledges ordered enqueueing
  /// and cannot await. Await `SubmissionReceipt.value()` for the publication outcome. A submission
  /// with `isFrame` may be superseded by a newer one when the queue is full.
  func submit(
    isFrame: Bool = false,
    whileActive: @escaping @Sendable () -> Bool = { true },
    requireActive: Bool = false,
    _ reports: @escaping @Sendable () throws -> [[UInt8]]
  ) -> SubmissionReceipt {
    let completion = SubmissionReceipt()
    let submission = Submission(
      completion: completion,
      isFrame: isFrame,
      whileActive: whileActive,
      requireActive: requireActive,
      reports: reports
    )
    let (result, superseded, start) = state.withLock {
      state -> (Result<Void, any Error>?, SubmissionReceipt?, Bool) in
      guard !state.closed else { return (.failure(CancellationError()), nil, false) }
      var superseded: SubmissionReceipt?
      if state.queue.count >= queueCapacity {
        guard let index = state.queue.firstIndex(where: \.isFrame) else {
          // The waiting host replies go first, so a frame that finds only replies is the
          // older state and yields to the next frame.
          return (.failure(isFrame ? Failure.superseded : Failure.queueOverflow), nil, false)
        }
        let evicted = state.queue.remove(at: index).completion
        state.pending.removeValue(forKey: ObjectIdentifier(evicted))
        superseded = evicted
      }
      state.pending[ObjectIdentifier(completion)] = completion
      state.queue.append(submission)
      let start = !state.running
      state.running = true
      return (nil, superseded, start)
    }
    superseded?.finish(.failure(Failure.superseded))
    if let result { completion.finish(result) }
    if start { chain.async { self.pump() } }
    return completion
  }

  /// Sends the waiting submissions in order on `chain`.
  ///
  /// It stops when none is left or when a send continues from its completion.
  private func pump() {
    while let taken = next() {
      let (submission, destination) = taken
      let reports: [[UInt8]]
      do {
        reports = try submission.reports()
      } catch {
        conclude(submission, .failure(error))
        continue
      }
      guard advance(submission, to: destination, reports: reports[...]) else { return }
    }
  }

  /// Takes the oldest waiting submission and marks it active; with none left, or once closed, it
  /// stops the queue and releases the closing task.
  private func next() -> (Submission, Destination)? {
    let (taken, failed, waiters) = state.withLock {
      state -> ((Submission, Destination)?, Submission?, [CheckedContinuation<Void, Never>]) in
      guard !state.queue.isEmpty else {
        state.running = false
        defer { state.releaseWaiters.removeAll() }
        return (nil, nil, state.releaseWaiters)
      }
      let submission = state.queue.removeFirst()
      guard !state.closed, let destination = state.destination else {
        return (nil, submission, [])
      }
      state.active = submission.completion
      return ((submission, destination), nil, [])
    }
    for waiter in waiters { waiter.resume() }
    if let failed {
      conclude(failed, .failure(CancellationError()))
      return next()
    }
    return taken
  }

  /// Sends `reports` of `submission` in order on `chain`.
  ///
  /// - Returns: False when a send continues from its completion.
  private func advance(
    _ submission: Submission,
    to destination: Destination,
    reports: ArraySlice<[UInt8]>
  ) -> Bool {
    var remaining = reports
    while let report = remaining.popFirst() {
      guard !state.withLock({ $0.closed }) else {
        conclude(submission, .failure(CancellationError()))
        return true
      }
      guard submission.whileActive() else {
        conclude(
          submission,
          submission.requireActive ? .failure(CancellationError()) : .success(())
        )
        return true
      }
      let rest = remaining
      let step = send(report, of: submission, to: destination) { [self] result in
        resume(submission, to: destination, reports: rest, after: result)
      }
      switch step {
      case .pending: return false
      case .finished(.failure(let error)):
        conclude(submission, .failure(error))
        return true
      case .finished(.success): continue
      }
    }
    conclude(submission, .success(()))
    return true
  }

  /// Continues `submission` on `chain` after a send that ended in its completion.
  ///
  /// It sends the rest of `reports`, then the waiting submissions.
  private func resume(
    _ submission: Submission,
    to destination: Destination,
    reports: ArraySlice<[UInt8]>,
    after result: Result<Void, any Error>
  ) {
    if case .failure(let error) = result {
      conclude(submission, .failure(error))
    } else if !advance(submission, to: destination, reports: reports) {
      return
    }
    pump()
  }

  /// Sends `report` of `submission` within the deadline.
  ///
  /// A blocking backend sends here and finishes; any other backend continues through `resume`
  /// on `chain`. When the deadline ends the send, `submission` fails at once and the waiting
  /// submissions follow on `chain`.
  private func send(
    _ report: [UInt8],
    of submission: Submission,
    to destination: Destination,
    resume: @escaping @Sendable (Result<Void, any Error>) -> Void
  ) -> Step {
    let operation = NativeSendOperation(watchdog: watchdog)
    state.withLock { state in
      state.operation = operation
      state.abandoned = false
    }
    operation.arm(backend: destination.backend) { [self] error in
      // A blocking send may still hold `chain`, so the submitter and the closing task learn of
      // the deadline on this thread; `chain` takes the next submission once it is free.
      let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
        state.abandoned = true
        defer { state.releaseWaiters.removeAll() }
        return state.releaseWaiters
      }
      for waiter in waiters { waiter.resume() }
      conclude(submission, .failure(error))
      chain.async { [self] in pump() }
    }
    if let blocking = destination.blocking {
      let result = Result { try blocking.sendBlocking(report) }
      return operation.end() ? .finished(result) : .pending
    }
    let cancelSend = destination.backend.startSend(report) { [chain] result in
      if operation.end() { chain.async { resume(result) } }
    }
    operation.setCancel(cancelSend)
    return .pending
  }

  /// Ends `submission` with `result` and forgets it.
  private func conclude(_ submission: Submission, _ result: Result<Void, any Error>) {
    state.withLock { state in
      state.pending.removeValue(forKey: ObjectIdentifier(submission.completion))
      if state.active === submission.completion { state.active = nil }
      state.operation = nil
    }
    submission.completion.finish(result)
  }

  /// Closes the sender without waiting; the returned task ends when the device is gone and the
  /// sender's queue has stopped or the deadline ended its send.
  @discardableResult
  func beginClose() -> Task<Void, Never> {
    let result = state.withLock {
      state -> (
        Task<Void, Never>, (any VirtualDeviceBackend)?,
        [SubmissionReceipt], NativeSendOperation?
      ) in
      if let closeTask = state.closeTask { return (closeTask, nil, [], nil) }
      state.closed = true
      state.queue.removeAll()
      let backend = state.destination?.backend
      state.destination = nil
      let activeIdentifier = state.active.map { ObjectIdentifier($0) }
      let cancellations = state.pending.compactMap { key, completion in
        key == activeIdentifier ? nil : completion
      }
      state.pending.removeAll()
      let operation = state.active == nil ? nil : state.operation
      let lock = self.state
      let sendWatchdog = watchdog
      let task = Task {
        // The backend is closed right after this task starts; wait until the native device is
        // gone, so a replacement is never published beside it.
        await backend?.waitUntilClosed()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          let released = lock.withLock { state -> Bool in
            if !state.running || state.abandoned { return true }
            state.releaseWaiters.append(continuation)
            return false
          }
          if released { continuation.resume() }
        }
        // The deadline bounds the last send until the queue stops.
        sendWatchdog.stop()
      }
      state.closeTask = task
      return (task, backend, cancellations, operation)
    }
    result.1?.close()
    for cancellation in result.2 { cancellation.finish(.failure(CancellationError())) }
    result.3?.cancel()
    return result.0
  }
}
