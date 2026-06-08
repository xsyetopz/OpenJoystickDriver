import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func requestAppInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    NSApp.activate(ignoringOtherApps: true)
    appInputMonitoring = "\(await permissionManager.requestAccess())"
    appInputMonitoring = await waitForAppInputMonitoringDecision()
    if appInputMonitoring != "granted" {
      openInputMonitoringSettings(for: ["OpenJoystickDriver"])
    }
  }

  func requestDaemonInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    if !daemonConnected {
      await recoverDaemonForInputMonitoringRequest()
    }

    do {
      try await requestBundledDaemonInputMonitoringPrompt()
    } catch {
      daemonError = error.localizedDescription
      return
    }

    if daemonConnected {
      do {
        inputMonitoring = try await client.requestInputMonitoringAccess()
      } catch {
        daemonError = formatDaemonError(error)
      }
    }

    inputMonitoring = await waitForDaemonInputMonitoringDecision()
    if inputMonitoring != "granted" {
      openInputMonitoringSettings(for: ["OpenJoystickDriver Daemon"])
    }
  }

  func waitForAppInputMonitoringDecision() async -> String {
    var state = appInputMonitoring
    for _ in 0..<inputMonitoringPromptPollAttempts {
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = "\(await permissionManager.checkAccess())"
      if state == "granted" { break }
    }
    return state
  }

  func waitForDaemonInputMonitoringDecision() async -> String {
    var state = inputMonitoring
    for _ in 0..<inputMonitoringPromptPollAttempts {
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      await syncFromDaemonNow()
      state = inputMonitoring
      if state == "granted" { break }
    }
    return state
  }

  func requestBundledDaemonInputMonitoringPrompt() async throws {
    let appURL = Bundle.main.bundleURL
    let promptEnvironment = ProcessInfo.processInfo.environment.merging(
      ["OJD_PERMISSION_PROMPT_ONLY": "1"]
    ) { _, new in new }

    if appURL.pathExtension == "app" {
      let daemonAppURL = DaemonManager.bundledDaemonApplicationURL(in: appURL)
      let executableURL = DaemonManager.bundledDaemonExecutableURL(in: appURL)
      let fileManager = FileManager.default
      guard fileManager.fileExists(atPath: daemonAppURL.path) else {
        throw NSError(
          domain: "OpenJoystickDriver",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              L10n.string("daemon.error.requestAccessMissingExecutable", daemonAppURL.path),
          ]
        )
      }
      guard fileManager.fileExists(atPath: executableURL.path) else {
        throw NSError(
          domain: "OpenJoystickDriver",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey:
              L10n.string("daemon.error.requestAccessMissingExecutable", executableURL.path),
          ]
        )
      }

      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      configuration.createsNewApplicationInstance = true
      configuration.environment = promptEnvironment
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        NSWorkspace.shared.openApplication(at: daemonAppURL, configuration: configuration) {
          _, error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
      return
    }

    let executableURL = DaemonManager.daemonExecutableURL(forMainBundleURL: appURL)
    guard FileManager.default.fileExists(atPath: executableURL.path) else {
      throw NSError(
        domain: "OpenJoystickDriver",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            L10n.string("daemon.error.requestAccessMissingExecutable", executableURL.path),
        ]
      )
    }

    let process = Process()
    process.executableURL = executableURL
    process.environment = promptEnvironment
    try process.run()
  }


  func recoverDaemonForInputMonitoringRequest() async {
    daemonError = nil
    daemonRestarting = true
    defer { daemonRestarting = false }

    guard ensureRunningFromApplications() else { return }
    guard ensureBundleSignatureValid(for: "Request Access") else { return }

    do {
      let shouldInstall = !daemonInstalled
      let shouldStart = daemonUIState == .stopped || daemonUIState == .unknown
      let task = Task.detached {
        if shouldInstall {
          try DaemonManager.install()
        } else if shouldStart {
          try DaemonManager.start()
        } else {
          try DaemonManager.restart()
        }
      }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }

    client.disconnect()
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    client.connect()
    await syncFromDaemonNow()
  }

  func openInputMonitoringSettings(
    for appNames: [String] = [
    L10n.string("app.name"),
    L10n.string("permissions.daemonName"),
  ]
  ) {
    let names = appNames.joined(separator: " and ")
    inputMonitoringAssist = L10n.string("permissions.assist", names)
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
