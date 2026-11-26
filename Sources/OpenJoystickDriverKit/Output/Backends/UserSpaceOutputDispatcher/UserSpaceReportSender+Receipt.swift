import Foundation

extension UserSpaceReportSender {
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
}
