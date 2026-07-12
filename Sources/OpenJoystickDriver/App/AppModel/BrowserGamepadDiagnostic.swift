import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func startBrowserGamepadDiagnostic(
    port: Int,
    seconds: Int,
    target: BrowserGamepadTarget
  ) async {
    stopBrowserGamepadDiagnostic()
    browserGamepadDiagnosticError = nil

    guard (1...65_535).contains(port) else {
      browserGamepadDiagnosticError = L10n.string("browserDiagnostic.invalidPort")
      return
    }
    guard (1...3_600).contains(seconds) else {
      browserGamepadDiagnosticError = L10n.string("browserDiagnostic.invalidDuration")
      return
    }

    do {
      let session = try BrowserGamepadDiagnosticService.start(port: port)
      browserGamepadDiagnosticSession = session
      browserGamepadDiagnosticURL = session.url
      browserGamepadDiagnosticRunning = true
      browserGamepadSnapshotCount = 0
      browserGamepadSnapshotPollTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          guard let self,
            self.browserGamepadDiagnosticSession?.id == session.id
          else { return }
          self.browserGamepadSnapshotCount = session.snapshotCount
          try? await Task.sleep(nanoseconds: 500_000_000)
        }
      }

      let warnings = await BrowserGamepadDiagnosticService.openAsync(
        session.url,
        target: target
      )
      guard browserGamepadDiagnosticSession?.id == session.id else { return }
      if !warnings.isEmpty {
        browserGamepadDiagnosticError = warnings.joined(separator: " ")
      }

      let sessionID = session.id
      browserGamepadDiagnosticStopTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        guard !Task.isCancelled,
          self?.browserGamepadDiagnosticSession?.id == sessionID
        else {
          return
        }
        self?.stopBrowserGamepadDiagnostic()
      }
    } catch {
      browserGamepadDiagnosticError = error.localizedDescription
      stopBrowserGamepadDiagnostic()
    }
  }

  func stopBrowserGamepadDiagnostic() {
    browserGamepadDiagnosticStopTask?.cancel()
    browserGamepadDiagnosticStopTask = nil
    browserGamepadSnapshotPollTask?.cancel()
    browserGamepadSnapshotPollTask = nil
    if let session = browserGamepadDiagnosticSession {
      browserGamepadSnapshotCount = session.snapshotCount
      session.stop()
    }
    browserGamepadDiagnosticSession = nil
    browserGamepadDiagnosticRunning = false
    browserGamepadDiagnosticURL = nil
  }
}
