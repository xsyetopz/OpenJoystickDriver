import Dispatch
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverPresentation
import OpenJoystickDriverService

#if canImport(AppIntents)
  import AppIntents
#endif
#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit
#endif

/// Keeps the signed application bundle alive while its in-process runtime owns
/// controller discovery, output, and the authenticated local RPC endpoint.
@MainActor
final class HeadlessApplicationHost {
  private let runtime = ApplicationServiceRuntime()
  #if canImport(AppKit) && canImport(SwiftUI)
    private var presentation: MenuBarCoordinator?
  #endif

  func run() -> Never {
    registerForLoginIfNeeded()
    #if canImport(AppKit) && canImport(SwiftUI)
      runtime.handleShutdownSignal { [weak runtime] in
        // terminate(_:) waits in a nested event loop for applicationShouldTerminate's asynchronous
        // reply, which needs the main queue. Starting it from a run-loop block instead of a
        // main-queue block or main-actor task keeps the main queue free to deliver that reply.
        RunLoop.main.perform {
          MainActor.assumeIsolated {
            if NSApplication.shared.isRunning,
              MenuBarCoordinator.terminateFromShutdownSignalIfRunning()
            {
              return
            }
            Task { @MainActor in
              await runtime?.stop()
              exit(0)
            }
          }
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
    #if canImport(AppIntents)
      if #available(macOS 13, *) {
        // The Shortcuts entity queries read the running service through this dependency.
        let automationService = runtime.automationService
        AppDependencyManager.shared.add(dependency: automationService)
      }
    #endif
    #if canImport(AppKit) && canImport(SwiftUI)
      presentation = MenuBarCoordinator(
        stopRuntime: { [runtime] in await runtime.stop() },
        gateway: ApplicationServiceClientGateway(),
        systemExtensionSetup: DefaultSystemExtensionSetupClient()
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

extension DefaultSystemExtensionSetupClient: SystemExtensionSetupClient {}
