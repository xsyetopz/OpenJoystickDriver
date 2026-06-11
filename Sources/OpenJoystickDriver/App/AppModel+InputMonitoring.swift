import AppKit
import CoreServices
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func requestAppInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    registerApplicationBundleForPermissionPrompt(Bundle.main.bundleURL)
    NSApp.activate(ignoringOtherApps: true)
    openInputMonitoringSettings(for: ["OpenJoystickDriver"])
    appInputMonitoring = "\(await permissionManager.requestAccess())"
    monitorAppInputMonitoringDecisionInBackground()
  }

  func requestDaemonInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    do {
      try await prepareDaemonRegistrationForPermissionPrompt()
    } catch {
      daemonError = error.localizedDescription
      return
    }

    openInputMonitoringSettings(for: ["OpenJoystickDriver"])
    appInputMonitoring = "\(await permissionManager.requestAccess())"
    inputMonitoring = appInputMonitoring
    monitorAppInputMonitoringDecisionInBackground()
    inputMonitoring = probeBundledDaemonInputMonitoringState()
    if inputMonitoring == "granted" {
      await recoverDaemonForInputMonitoringRequest()
      return
    }

    monitorDaemonInputMonitoringDecisionInBackground()
  }

  func prepareDaemonRegistrationForPermissionPrompt() async throws {
    guard ensureRunningFromApplications() else {
      throw NSError(
        domain: "OpenJoystickDriver",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Request Access requires /Applications/OpenJoystickDriver.app.",
        ]
      )
    }
    guard ensureBundleSignatureValid(for: "Request Access") else {
      throw NSError(
        domain: "OpenJoystickDriver",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Request Access requires a valid signed OpenJoystickDriver.app bundle.",
        ]
      )
    }

    guard !daemonInstalled else { return }
    let task = Task.detached { try DaemonManager.install() }
    try await task.value
    try? await Task.sleep(nanoseconds: 500_000_000)
    refreshDaemonStatus()
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
    var state = probeBundledDaemonInputMonitoringState()
    for _ in 0..<inputMonitoringPromptPollAttempts {
      if state == "granted" { break }
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = probeBundledDaemonInputMonitoringState()
    }
    return state
  }

  func monitorAppInputMonitoringDecisionInBackground() {
    Task { [weak self] in
      guard let self else { return }
      let state = await waitForAppInputMonitoringDecision()
      appInputMonitoring = state
    }
  }

  func monitorDaemonInputMonitoringDecisionInBackground() {
    Task { [weak self] in
      guard let self else { return }
      let state = await waitForDaemonInputMonitoringDecision()
      inputMonitoring = state
      guard state == "granted" else { return }
      await recoverDaemonForInputMonitoringRequest()
    }
  }

  func probeBundledDaemonInputMonitoringState() -> String {
    let executableURL = DaemonManager.daemonExecutableURL(forMainBundleURL: Bundle.main.bundleURL)
    guard FileManager.default.fileExists(atPath: executableURL.path) else { return "unknown" }

    let process = Process()
    process.executableURL = executableURL
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["OJD_PERMISSION_CHECK_ONLY": "1"]
    ) { _, new in new }
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      print("[AppModel] Failed to probe daemon Input Monitoring state: \(error)")
      return "unknown"
    }

    guard process.terminationStatus == 0 else { return "unknown" }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(bytes: data, encoding: .utf8) else {
      return "unknown"
    }
    for line in output.split(whereSeparator: \.isNewline).reversed() {
      let state = line.trimmingCharacters(in: .whitespacesAndNewlines)
      switch state {
      case "granted", "denied", "unknown":
        return state
      default:
        continue
      }
    }
    return "unknown"
  }

  @discardableResult
  func registerApplicationBundleForPermissionPrompt(_ appURL: URL) -> Bool {
    guard appURL.pathExtension == "app" else { return false }
    let status = LSRegisterURL(appURL as CFURL, true)
    if status != noErr {
      print(
        "[AppModel] LaunchServices registration failed for "
          + "\(appURL.path): \(status)"
      )
    }
    return status == noErr
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
