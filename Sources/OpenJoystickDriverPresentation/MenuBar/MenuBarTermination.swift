#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit

  /// All quit sources wait for the same teardown.
  ///
  /// TCC owns its native reopen.
  @MainActor
  final class MenuBarTermination {
    /// The stages of a quit: running, waiting for the teardown, and done.
    private enum State {
      /// No quit has started.
      case running
      /// A quit waits for the teardown.
      case stopping
      /// The teardown has finished.
      case stopped
    }
    /// The current stage of the quit.
    private var state = State.running
    /// Whether a relaunch follows the teardown.
    private var relaunchRequested = false

    /// Terminates through `terminate` and relaunches after the teardown.
    ///
    /// Does nothing once a quit has started or a relaunch is requested.
    func requestRelaunch(terminate: () -> Void) {
      guard state == .running, !relaunchRequested else { return }
      relaunchRequested = true
      terminate()
    }

    /// Returns the reply to the app's quit request.
    ///
    /// The first call runs `stop`, then `relaunch` when requested, then `reply`, and returns
    /// `.terminateLater`. A call during the teardown also returns `.terminateLater`, and a call
    /// after it returns `.terminateNow`.
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
