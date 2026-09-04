import Dispatch
import Foundation
import OpenJoystickDriverKit

#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit
#endif

/// Keeps the signed application bundle alive while its in-process runtime owns
/// controller discovery, output, and the authenticated local RPC endpoint.
final class HeadlessApplicationHost {
  private let runtime = ApplicationServiceRuntime()
  #if canImport(AppKit) && canImport(SwiftUI)
    private var presentation: MenuBarCoordinator?
  #endif

  @MainActor func run() -> Never {
    registerForLoginIfNeeded()
    #if canImport(AppKit) && canImport(SwiftUI)
      runtime.handleShutdownSignal { [weak runtime] in
        Task { @MainActor in
          if NSApplication.shared.isRunning,
            MenuBarCoordinator.terminateFromShutdownSignalIfRunning()
          {
            return
          }
          await runtime?.stop()
          exit(0)
        }
      }
    #endif
    do { try runtime.start() } catch {
      fputs(
        "[OpenJoystickDriver] Main-app service startup failed: \(error.localizedDescription)\n",
        stderr
      )
      exit(EXIT_FAILURE)
    }
    #if canImport(AppKit) && canImport(SwiftUI)
      presentation = MenuBarCoordinator(
        runtime: runtime,
        gateway: ApplicationServiceClientGateway()
      )
      guard let presentation else { dispatchMain() }
      presentation.run()
    #else
      dispatchMain()
    #endif
  }

  private func registerForLoginIfNeeded() {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    do { try ApplicationServiceManager.installByDefaultIfNeeded() } catch {
      fputs(
        "[OpenJoystickDriver] Login registration unavailable: \(error.localizedDescription)\n",
        stderr
      )
    }
  }
}
