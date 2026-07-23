import Dispatch
import Foundation
import OpenJoystickDriverKit

/// Keeps the signed application bundle alive while its in-process runtime owns
/// controller discovery, output, and the authenticated local RPC endpoint.
final class HeadlessApplicationHost {
  private let runtime = ApplicationServiceRuntime()

  func run() -> Never {
    registerForLoginIfNeeded()
    runtime.start()
    dispatchMain()
  }

  private func registerForLoginIfNeeded() {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    do {
      try ApplicationServiceManager.installByDefaultIfNeeded()
    } catch {
      fputs(
        "[OpenJoystickDriver] Login registration unavailable: \(error.localizedDescription)\n",
        stderr
      )
    }
  }
}
