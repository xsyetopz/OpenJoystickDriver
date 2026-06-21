import Foundation
import Testing

struct InputMonitoringPromptFlowTests {
  @Test
  func testDaemonHelperUsesAppLifecycleForPermissionPrompt() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let daemonMainURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/main.swift"
    )
    let launchAgentURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
    )
    let daemonMain = try String(contentsOf: daemonMainURL, encoding: .utf8)
    let launchAgent = try String(contentsOf: launchAgentURL, encoding: .utf8)

    #expect(daemonMain.contains("PermissionPromptAppDelegate"))
    #expect(daemonMain.contains("NSApplication.shared.run()"))
    #expect(daemonMain.contains("let permissionCheckOnlyMode ="))
    #expect(daemonMain.contains("OJD_PERMISSION_CHECK_ONLY"))
    #expect(daemonMain.contains("PermissionManager.currentAccessState()"))
    #expect(daemonMain.contains("Starting permission-check probe mode"))
    #expect(daemonMain.contains("let promptOnlyMode ="))
    #expect(daemonMain.contains("commandLineArguments.contains(\"--request-input-monitoring\")"))
    #expect(daemonMain.contains("commandLineArguments.contains(\"--request-accessibility\")"))
    #expect(daemonMain.contains("OJD_ACCESSIBILITY_CHECK_ONLY"))
    #expect(daemonMain.contains("OJD_ACCESSIBILITY_PROMPT_ONLY"))
    #expect(daemonMain.contains("PermissionPromptAppDelegate.PromptKind"))
    #expect(
      daemonMain.contains(
        "environment[\"OJD_PERMISSION_PROMPT_ONLY\"] == \"1\""
      )
    )
    #expect(daemonMain.contains("timeoutNanoseconds: UInt64 = 120_000_000_000"))
    #expect(daemonMain.contains("Starting permission prompt helper mode"))
    #expect(daemonMain.contains("Starting daemon service mode"))
    #expect(daemonMain.contains("denied for daemon helper app"))
    #expect(daemonMain.contains("if initialState == .denied"))
    #expect(daemonMain.contains("if state == .denied"))
    #expect(!daemonMain.contains("DispatchSemaphore"))
    #expect(!daemonMain.contains("semaphore.wait()"))
    #expect(!daemonMain.contains("Thread.sleep(forTimeInterval: 5)"))
    #expect(launchAgent.contains("<key>EnvironmentVariables</key>"))
    #expect(launchAgent.contains("<key>OJD_LAUNCHD_DAEMON</key>"))
  }

  @Test
  func testGuiLaunchesDaemonHelperAppInsteadOfRequestingPermissionOverXPC() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let deviceManagerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager.swift"
    )
    let source = try String(contentsOf: inputMonitoringURL, encoding: .utf8)
    let compactSource = source.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    )
    let deviceManager = try String(contentsOf: deviceManagerURL, encoding: .utf8)

    #expect(source.contains("NSWorkspace.OpenConfiguration()"))
    #expect(source.contains("configuration.createsNewApplicationInstance = true"))
    #expect(source.contains("configuration.arguments = [appArgument]"))
    #expect(source.contains("--request-input-monitoring"))
    #expect(source.contains("--request-accessibility"))
    #expect(!source.contains("configuration.environment = promptEnvironment"))
    #expect(!source.contains("client.requestInputMonitoringAccess()"))
    #expect(source.contains("try await prepareDaemonRegistrationForPermissionPrompt()"))
    #expect(source.contains("try await requestBundledDaemonInputMonitoringPrompt()"))
    #expect(source.contains("inputMonitoring = await waitForDaemonInputMonitoringDecision()"))
    #expect(source.contains("probeBundledDaemonInputMonitoringState()"))
    #expect(source.contains("\"OJD_PERMISSION_CHECK_ONLY\""))
    #expect(source.contains("\"OJD_ACCESSIBILITY_CHECK_ONLY\""))
    #expect(source.contains("guard !daemonInstalled else { return }"))
    #expect(source.contains("let task = Task.detached { try DaemonManager.install() }"))
    let promptLaunchRange = source.firstRange(
      of: "try await prepareDaemonRegistrationForPermissionPrompt()"
    )
    let helperLaunchRange = source.firstRange(
      of: "try await requestBundledDaemonInputMonitoringPrompt()"
    )
    let waitRange = source.firstRange(
      of: "inputMonitoring = await waitForDaemonInputMonitoringDecision()"
    )
    let daemonRecoveryRange = source.firstRange(
      of: "await recoverDaemonForInputMonitoringRequest()"
    )
    #expect(promptLaunchRange != nil)
    #expect(helperLaunchRange != nil)
    #expect(waitRange != nil)
    #expect(daemonRecoveryRange != nil)
    if let promptLaunchRange, let helperLaunchRange, let waitRange, let daemonRecoveryRange {
      #expect(promptLaunchRange.lowerBound < helperLaunchRange.lowerBound)
      #expect(helperLaunchRange.lowerBound < waitRange.lowerBound)
      #expect(waitRange.lowerBound < daemonRecoveryRange.lowerBound)
    }
    #expect(source.contains("if inputMonitoring == \"granted\""))
    #expect(compactSource.contains("if daemonConnected { await syncFromDaemonNow() }"))
    #expect(source.contains("process.environment = ProcessInfo.processInfo.environment.merging"))
    #expect(source.contains("\"OJD_PERMISSION_PROMPT_ONLY\""))
    #expect(source.contains("\"OJD_ACCESSIBILITY_PROMPT_ONLY\""))
    #expect(!deviceManager.contains("await permissionManager.requestAccess()"))
    #expect(deviceManager.contains("Use the app's Request Access action"))
    let hidDetectionURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager+HIDDetection.swift"
    )
    let hidDetection = try String(contentsOf: hidDetectionURL, encoding: .utf8)
    #expect(deviceManager.contains("await ensureHIDDetectionState(for: state)"))
    #expect(hidDetection.contains("func ensureHIDDetectionState"))
    #expect(hidDetection.contains("await removeHIDPipelines()"))
  }
  @Test
  func testDaemonRetainsShutdownSignalSourcesForQuitAndReopen() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let shutdownURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager+Shutdown.swift"
    )
    let source = try String(contentsOf: shutdownURL, encoding: .utf8)

    #expect(source.contains("ShutdownSignalSourceStore"))
    #expect(source.contains("private var sources: [DispatchSourceSignal] = []"))
    #expect(source.contains("shutdownSignalSourceStore.retain(sigterm)"))
    #expect(source.contains("shutdownSignalSourceStore.retain(sigint)"))
    #expect(source.contains("signal(SIGTERM, SIG_IGN)"))
    #expect(source.contains("signal(SIGINT, SIG_IGN)"))
  }

}
