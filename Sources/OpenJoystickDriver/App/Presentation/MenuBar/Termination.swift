#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit

  /// All quit sources wait for the same teardown. TCC owns its native reopen.
  @MainActor final class MenuBarTermination {
    private enum State { case running, stopping, stopped }
    private var state = State.running

    func request(
      stop: @escaping @MainActor () async -> Void,
      reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
      switch state {
      case .stopped: return .terminateNow
      case .stopping: return .terminateLater
      case .running:
        state = .stopping
        Task { @MainActor in
          await stop()
          self.state = .stopped
          reply()
        }
        return .terminateLater
      }
    }
  }
#endif
