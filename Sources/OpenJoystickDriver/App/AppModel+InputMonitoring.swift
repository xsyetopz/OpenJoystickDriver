import AppKit
import CoreServices
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  func requestAppInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    registerApplicationBundleForPermissionPrompt(Bundle.main.bundleURL)
    NSApp.activate(ignoringOtherApps: true)
    appInputMonitoring = "\(await permissionManager.requestAccess())"
    appInputMonitoring = await waitForAppInputMonitoringDecision()
    if appInputMonitoring != "granted" { openInputMonitoringSettings(for: ["OpenJoystickDriver"]) }
  }

  func requestAppAccessibilityAccess() async {
    inputMonitoringAssist = nil
    registerApplicationBundleForPermissionPrompt(Bundle.main.bundleURL)
    NSApp.activate(ignoringOtherApps: true)
    appAccessibility = "\(await permissionManager.requestAccessibilityAccess())"
    appAccessibility = await waitForAppAccessibilityDecision()
    if appAccessibility != "granted" { openAccessibilitySettings() }
  }

  func requestDaemonAccessibilityAccess() async {
    inputMonitoringAssist = nil
    do {
      try await prepareDaemonRegistrationForPermissionPrompt()
      try await requestBundledDaemonAccessibilityPrompt()
    } catch {
      daemonError = error.localizedDescription
      return
    }

    daemonAccessibility = await waitForDaemonAccessibilityDecision()
    if daemonAccessibility != "granted" { openAccessibilitySettings() }
  }

  func requestDaemonInputMonitoringAccess() async {
    inputMonitoringAssist = nil
    do {
      try await prepareDaemonRegistrationForPermissionPrompt()
      try await requestBundledDaemonInputMonitoringPrompt()
    } catch {
      daemonError = error.localizedDescription
      return
    }

    inputMonitoring = await waitForDaemonInputMonitoringDecision()
    if inputMonitoring == "granted" {
      if !daemonConnected {
        await recoverDaemonForInputMonitoringRequest()
      } else {
        await syncFromDaemonNow()
      }
      inputMonitoring = probeBundledDaemonInputMonitoringState()
      return
    }

    if daemonConnected { await syncFromDaemonNow() }

    if inputMonitoring != "granted" {
      openInputMonitoringSettings(for: ["OpenJoystickDriver Daemon"])
    }
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

  func waitForAppAccessibilityDecision() async -> String {
    var state = appAccessibility
    for _ in 0..<inputMonitoringPromptPollAttempts {
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = "\(await permissionManager.checkAccessibilityAccess())"
      if state == "granted" { break }
    }
    return state
  }

  func waitForDaemonInputMonitoringDecision() async -> String {
    var state = probeBundledDaemonInputMonitoringState()
    for _ in 0..<inputMonitoringPromptPollAttempts {
      if state == "granted" || state == "denied" { break }
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = probeBundledDaemonInputMonitoringState()
    }
    return state
  }

  func waitForDaemonAccessibilityDecision() async -> String {
    var state = probeBundledDaemonAccessibilityState()
    for _ in 0..<inputMonitoringPromptPollAttempts {
      if state == "granted" || state == "denied" { break }
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = probeBundledDaemonAccessibilityState()
    }
    return state
  }

  func probeBundledDaemonAccessibilityState() -> String {
    probeBundledDaemonPermissionState(environmentKey: "OJD_ACCESSIBILITY_CHECK_ONLY")
  }

  func probeBundledDaemonInputMonitoringState() -> String {
    probeBundledDaemonPermissionState(environmentKey: "OJD_PERMISSION_CHECK_ONLY")
  }

  func probeBundledDaemonPermissionState(environmentKey: String) -> String {
    let executableURL = DaemonManager.daemonExecutableURL(forMainBundleURL: Bundle.main.bundleURL)
    guard FileManager.default.fileExists(atPath: executableURL.path) else { return "unknown" }

    let process = Process()
    process.executableURL = executableURL
    process.environment = ProcessInfo.processInfo.environment.merging([
      environmentKey: "1",
    ]) { _, new in new }
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
    guard
      let state = String(bytes: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
    else { return "unknown" }
    switch state {
    case "granted", "denied", "unknown": return state
    default: return "unknown"
    }
  }

  func requestBundledDaemonAccessibilityPrompt() async throws {
    try await requestBundledDaemonPermissionPrompt(
      appArgument: "--request-accessibility",
      environmentKey: "OJD_ACCESSIBILITY_PROMPT_ONLY"
    )
  }

  func requestBundledDaemonInputMonitoringPrompt() async throws {
    try await requestBundledDaemonPermissionPrompt(
      appArgument: "--request-input-monitoring",
      environmentKey: "OJD_PERMISSION_PROMPT_ONLY"
    )
  }

  func requestBundledDaemonPermissionPrompt(
    appArgument: String,
    environmentKey: String
  ) async throws {
    let appURL = Bundle.main.bundleURL

    if appURL.pathExtension == "app" {
      let daemonAppURL = DaemonManager.bundledDaemonApplicationURL(in: appURL)
      let executableURL = DaemonManager.bundledDaemonExecutableURL(in: appURL)
      let fileManager = FileManager.default
      guard fileManager.fileExists(atPath: daemonAppURL.path) else {
        throw NSError(
          domain: "OpenJoystickDriver",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: L10n.string(
              "daemon.error.requestAccessMissingExecutable",
              daemonAppURL.path
            ),
          ]
        )
      }
      guard fileManager.fileExists(atPath: executableURL.path) else {
        throw NSError(
          domain: "OpenJoystickDriver",
          code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: L10n.string(
              "daemon.error.requestAccessMissingExecutable",
              executableURL.path
            ),
          ]
        )
      }

      registerApplicationBundleForPermissionPrompt(daemonAppURL)

      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      configuration.createsNewApplicationInstance = true
      configuration.arguments = [appArgument]
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        NSWorkspace.shared.openApplication(at: daemonAppURL, configuration: configuration) {
          _,
          error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
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
          NSLocalizedDescriptionKey: L10n.string(
            "daemon.error.requestAccessMissingExecutable",
            executableURL.path
          ),
        ]
      )
    }

    let process = Process()
    process.executableURL = executableURL
    process.environment = ProcessInfo.processInfo.environment.merging([
      environmentKey: "1",
    ]) { _, new in new }
    try process.run()
  }

  @discardableResult func registerApplicationBundleForPermissionPrompt(_ appURL: URL) -> Bool {
    guard appURL.pathExtension == "app" else { return false }
    let status = LSRegisterURL(appURL as CFURL, true)
    if status != noErr {
      print("[AppModel] LaunchServices registration failed for " + "\(appURL.path): \(status)")
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

  func openAccessibilitySettings() {
    inputMonitoringAssist = "If macOS asks for Accessibility, enable OpenJoystickDriver "
      + "or OpenJoystickDriver Daemon in System Settings."
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
    if let url, NSWorkspace.shared.open(url) { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  func openInputMonitoringSettings(
    for appNames: [String] = [L10n.string("app.name"), L10n.string("permissions.daemonName")]
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
