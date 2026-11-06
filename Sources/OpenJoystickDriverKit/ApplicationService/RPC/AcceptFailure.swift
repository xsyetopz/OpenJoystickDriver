import Darwin
import Foundation

/// What an accept loop does after `accept` fails; the RPC server and the endpoint server share it.
package enum AcceptFailure: Equatable, Sendable {
  /// The connection was dropped or the call interrupted, or none was waiting; accept again at
  /// once.
  case retry
  /// The process or system is out of descriptors or memory. Connections wait in the queue; the
  /// loop reports the reason, waits and accepts again.
  case waitForResources
  /// The listening socket is unusable, so the loop ends.
  case fatal

  /// Milliseconds an accept loop waits after `waitForResources`.
  package static let resourceWaitMilliseconds: Int32 = 500

  /// Classifies the error number `code` of a failed `accept`.
  package init(errno code: Int32) {
    switch code {
    case EINTR, ECONNABORTED, EAGAIN: self = .retry
    case EMFILE, ENFILE, ENOBUFS, ENOMEM: self = .waitForResources
    default: self = .fatal
    }
  }

  /// The line that reports a failure of the accept loop of `server`.
  ///
  /// A fatal one carries `ended`, the code that explains to the user what stopped.
  package static func message(
    server: String,
    errno code: Int32,
    action: Self,
    waitMilliseconds: Int32 = resourceWaitMilliseconds,
    ended: ErrorCode? = nil
  ) -> String {
    let reason = String(cString: strerror(code))
    switch action {
    case .waitForResources:
      return "[\(server)] Cannot accept connections (\(reason), errno \(code)); "
        + "retrying in \(waitMilliseconds) ms"
    case .retry, .fatal:
      let explanation = ended.map { "\($0.rawValue): \($0.localizedExplanation) " } ?? ""
      return "[\(server)] \(explanation)Stopped accepting connections (\(reason), errno \(code))"
    }
  }

  /// What an accept loop does next after a failure.
  package enum Continuation: Equatable, Sendable {
    /// Accept again.
    case goOn
    /// The server was stopped while the loop waited for resources.
    case stopped
    /// The loop ends on its own, with this error number.
    case ended(Int32)
  }

  /// Applies the failure `code` of the accept loop of `server` and returns whether the loop goes
  /// on.
  package static func continuesAfter(
    errno code: Int32,
    server: String,
    wake: Int32,
    waitMilliseconds: Int32 = resourceWaitMilliseconds,
    ended: ErrorCode? = nil,
    pollCall: PollCall = Darwin.poll,
    report: (String) -> Void
  ) -> Bool {
    continuation(
      errno: code,
      server: server,
      wake: wake,
      waitMilliseconds: waitMilliseconds,
      ended: ended,
      pollCall: pollCall,
      report: report
    ) == .goOn
  }

  /// Applies the failure `code` of the accept loop of `server` and returns what the loop does next.
  ///
  /// A wait for resources ends early, and the loop stops, when `wake` becomes readable or hangs
  /// up.
  package static func continuation(
    errno code: Int32,
    server: String,
    wake: Int32,
    waitMilliseconds: Int32 = resourceWaitMilliseconds,
    ended: ErrorCode? = nil,
    pollCall: PollCall = Darwin.poll,
    report: (String) -> Void
  ) -> Continuation {
    let action = Self(errno: code)
    switch action {
    case .retry: return .goOn
    case .waitForResources:
      report(
        message(server: server, errno: code, action: action, waitMilliseconds: waitMilliseconds)
      )
      switch wait(milliseconds: waitMilliseconds, wake: wake, pollCall: pollCall) {
      case .elapsed: return .goOn
      case .woken: return .stopped
      case .failed(let pollCode):
        report(message(server: server, errno: pollCode, action: .fatal, ended: ended))
        return .ended(pollCode)
      }
    case .fatal:
      report(message(server: server, errno: code, action: action, ended: ended))
      return .ended(code)
    }
  }

  /// `poll`, as tests replace it to fail the call.
  package typealias PollCall = (UnsafeMutablePointer<pollfd>, nfds_t, Int32) -> Int32

  /// How a wait for resources ended.
  package enum Wait: Equatable, Sendable {
    /// The time passed; accept again.
    case elapsed
    /// `wake` became readable or hung up: the server was stopped.
    case woken
    /// `poll` failed with this error number.
    case failed(Int32)
  }

  /// Waits up to `milliseconds` for `wake` to become readable or hang up.
  package static func wait(
    milliseconds: Int32,
    wake: Int32,
    pollCall: PollCall = Darwin.poll
  ) -> Wait {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(milliseconds) * 1_000_000
    while true {
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else { return .elapsed }
      let remaining = Int32(min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max)))
      var polled = [pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
      let ready = pollCall(&polled, 1, remaining)
      if ready < 0 {
        if errno == EINTR { continue }
        return .failed(errno)
      }
      if polled[0].revents & Int16(POLLNVAL) != 0 { return .failed(EBADF) }
      if polled[0].revents != 0 { return .woken }
    }
  }
}
