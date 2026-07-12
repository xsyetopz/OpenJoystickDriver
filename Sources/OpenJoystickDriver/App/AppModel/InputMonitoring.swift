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
    if appInputMonitoring != "granted" {
      openInputMonitoringSettings(for: ["OpenJoystickDriver"])
    }
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
      inputMonitoring = await probeBundledDaemonInputMonitoringState()
      return
    }

    if daemonConnected {
      await syncFromDaemonNow()
    }

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
    guard await ensureBundleSignatureValid(for: "Request Access") else {
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
    var state = await probeBundledDaemonInputMonitoringState()
    for _ in 0..<inputMonitoringPromptPollAttempts {
      if state == "granted" || state == "denied" { break }
      try? await Task.sleep(nanoseconds: inputMonitoringPromptPollNanoseconds)
      state = await probeBundledDaemonInputMonitoringState()
    }
    return state
  }

  func probeBundledDaemonInputMonitoringState() async -> String {
    let state = await PermissionManager.daemonAccessStateAsync(
      mainBundleURL: Bundle.main.bundleURL
    )
    return state.description
  }

  func requestBundledDaemonInputMonitoringPrompt() async throws {
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

      registerApplicationBundleForPermissionPrompt(daemonAppURL)

      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      configuration.createsNewApplicationInstance = true
      configuration.arguments = ["--request-input-monitoring"]
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
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["OJD_PERMISSION_PROMPT_ONLY": "1"]
    ) { _, new in new }
    try process.run()
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
    guard await ensureBundleSignatureValid(for: "Request Access") else { return }

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

  func refreshStaleInputMonitoringPermissions() async {
    daemonError = nil
    daemonRestarting = true
    defer { daemonRestarting = false }

    let result: Result<Void, Error> = await Task.detached {
      do {
        for identifier in ["com.openjoystickdriver", "com.openjoystickdriver.daemon"] {
          let reset = try BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
            arguments: ["reset", "ListenEvent", identifier],
            timeoutSeconds: 5,
            maximumOutputBytes: 65_536
          )
          guard !reset.timedOut, reset.terminationStatus == 0 else {
            throw NSError(
              domain: "OpenJoystickDriver.PermissionRefresh",
              code: Int(reset.terminationStatus),
              userInfo: [NSLocalizedDescriptionKey: reset.output]
            )
          }
        }
        if DaemonManager.isInstalled { try DaemonManager.uninstall() }
        try DaemonManager.install()
        return .success(())
      } catch {
        return .failure(error)
      }
    }.value

    switch result {
    case .success:
      appInputMonitoring = "unknown"
      inputMonitoring = "unknown"
      inputMonitoringAssist =
        "Old Input Monitoring decisions were removed. Request access again for each OJD item."
      client.disconnect()
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      client.connect()
      openInputMonitoringSettings()
    case .failure(let error):
      daemonError = error.localizedDescription
    }
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
