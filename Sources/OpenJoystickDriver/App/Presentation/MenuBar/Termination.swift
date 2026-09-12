#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit

  /// All quit sources wait for the same teardown. TCC owns its native reopen.
  @MainActor
  final class MenuBarTermination {
    private enum State { case running, stopping, stopped }
    private var state = State.running
    private var relaunchRequested = false

    func requestRelaunch(terminate: () -> Void) {
      guard state == .running, !relaunchRequested else { return }
      relaunchRequested = true
      terminate()
    }

    func request(
      stop: @escaping @MainActor () async -> Void,
      relaunch: @escaping @MainActor () async -> Void = {},
      reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
      switch state {
      case .stopped: return .terminateNow
      case .stopping: return .terminateLater
      case .running:
        state = .stopping
        Task { @MainActor in
          await stop()
          if self.relaunchRequested { await relaunch() }
          self.state = .stopped
          reply()
        }
        return .terminateLater
      }
    }
  }
#endif
