import AppKit
import Foundation
import OpenJoystickDriverKit

private let daemonLifecycleTimeoutNanoseconds: UInt64 = 8_000_000_000

private struct DaemonLifecycleTimeoutError: LocalizedError {
  var errorDescription: String? {
    "Daemon operation timed out. Quit OpenJoystickDriver, reopen it, then try again."
  }
}

private final class DaemonLifecycleCompletionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var didResume = false

  func resumeOnce(_ body: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !didResume else { return }
    didResume = true
    body()
  }
}

@MainActor extension AppModel {
  // MARK: - Daemon lifecycle

  func installDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Install") else { return }
    do {
      try await runDaemonLifecycleOperation { try DaemonManager.install() }
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func startDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Start") else { return }
    do {
      try await runDaemonLifecycleOperation { try DaemonManager.start() }
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func restartDaemon() async {
    daemonError = nil
    daemonRestarting = true
    guard ensureRunningFromApplications() else {
      daemonRestarting = false
      return
    }
    guard ensureBundleSignatureValid(for: "Restart") else {
      daemonRestarting = false
      return
    }
    do {
      try await runDaemonLifecycleOperation { try DaemonManager.restart() }
    } catch {
      daemonError = error.localizedDescription
      daemonRestarting = false
      return
    }
    client.disconnect()
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    client.connect()
    await syncFromDaemonNow()
    daemonRestarting = false
  }

  func uninstallDaemon() async {
    daemonError = nil
    daemonRestarting = true
    defer { daemonRestarting = false }
    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Uninstall") else { return }
    do {
      try await runDaemonLifecycleOperation { try DaemonManager.uninstall() }
    } catch {
      daemonError = error.localizedDescription
      return
    }
    client.disconnect()
    await syncFromDaemonNow()
  }

  func runDaemonLifecycleOperation(
    _ operation: @escaping @Sendable () throws -> Void
  ) async throws {
    let operationTask = Task.detached {
      try operation()
    }

    try await withCheckedThrowingContinuation { continuation in
      let completion = DaemonLifecycleCompletionBox()

      Task.detached {
        do {
          try await operationTask.value
          completion.resumeOnce {
            continuation.resume(returning: ())
          }
        } catch {
          completion.resumeOnce {
            continuation.resume(throwing: error)
          }
        }
      }

      let timeoutMilliseconds = Int(daemonLifecycleTimeoutNanoseconds / 1_000_000)
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + .milliseconds(timeoutMilliseconds)
      ) {
        operationTask.cancel()
        completion.resumeOnce {
          continuation.resume(throwing: DaemonLifecycleTimeoutError())
        }
      }
    }
  }
}
