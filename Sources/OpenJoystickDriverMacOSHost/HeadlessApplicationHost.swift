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
  #if canImport(AppKit) && canImport(SwiftUI)
    /// The menu bar item of the app, when the app has a presentation layer.
    private var presentation: MenuBarCoordinator?
  #endif

  /// Starts the service runtime and runs the main loop; it never returns.
  func run() -> Never {
    registerForLoginIfNeeded()
    let runtime: ApplicationServiceRuntime
    do { runtime = try ApplicationServiceRuntime() } catch { failStartup(error) }
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
    do { try runtime.start() } catch { failStartup(error) }
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
        systemExtensionSetup: DefaultSystemExtensionSetupClient(),
        listenerState: runtime.listenerState
      )
      guard let presentation else { dispatchMain() }
      presentation.run()
    #else
      dispatchMain()
    #endif
  }

  /// Prints why the service cannot start and exits.
  ///
  /// The service never runs without its port key or its runtime.
  private func failStartup(_ error: any Error) -> Never {
    fputs(
      "[OpenJoystickDriver] Main-app service startup failed: \(error.localizedDescription)\n",
      stderr
    )
    exit(EXIT_FAILURE)
  }

  /// Registers the app as a login item when it runs from an app bundle.
  ///
  /// A settings file that cannot be read skips the registration, because the opt-out is unknown.
  private func registerForLoginIfNeeded() {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    do { try ApplicationServiceManager.installByDefaultIfNeeded() } catch let error
      as SettingsStoreError
    {
      // The opt-out is unknown while the settings file can't be read, so no login item is added.
      fputs(
        "[OpenJoystickDriver] Login registration skipped, the settings file cannot be read: "
          + "\(error.localizedDescription)\n",
        stderr
      )
    } catch {
      fputs(
        "[OpenJoystickDriver] Login registration unavailable: \(error.localizedDescription)\n",
        stderr
      )
    }
  }
}

extension DefaultSystemExtensionSetupClient: SystemExtensionSetupClient {}
