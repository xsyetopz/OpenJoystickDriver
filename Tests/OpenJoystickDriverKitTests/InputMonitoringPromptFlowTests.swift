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
    #expect(
      !daemonMain.contains(
        "daemonLog(\"[Daemon] Starting permission-check probe mode\")"
      )
    )
    #expect(daemonMain.contains("let promptOnlyMode ="))
    #expect(daemonMain.contains("commandLineArguments.contains(\"--request-input-monitoring\")"))
    #expect(
      daemonMain.contains(
        "environment[\"OJD_PERMISSION_PROMPT_ONLY\"] == \"1\""
      )
    )
    #expect(daemonMain.contains("timeoutNanoseconds: UInt64 = 120_000_000_000"))
    #expect(daemonMain.contains("Starting permission prompt helper mode"))
    #expect(daemonMain.contains("Starting daemon service mode"))
    #expect(daemonMain.contains("Input Monitoring approval pending for daemon helper app"))
    #expect(!daemonMain.contains("if initialState == .denied"))
    #expect(!daemonMain.contains("if state == .denied"))
    #expect(!daemonMain.contains("Input Monitoring denied for daemon helper app"))
    #expect(!daemonMain.contains("DispatchSemaphore"))
    #expect(!daemonMain.contains("semaphore.wait()"))
    #expect(!daemonMain.contains("Thread.sleep(forTimeInterval: 5)"))
    #expect(launchAgent.contains("<key>EnvironmentVariables</key>"))
    #expect(launchAgent.contains("<key>OJD_LAUNCHD_DAEMON</key>"))
  }

  @Test
  func testGuiRequestsMainAppPermissionForDaemonBackend() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let deviceManagerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager.swift"
    )
    let source = try String(contentsOf: inputMonitoringURL, encoding: .utf8)
    let deviceManager = try String(contentsOf: deviceManagerURL, encoding: .utf8)

    #expect(!source.contains("NSWorkspace.OpenConfiguration()"))
    #expect(!source.contains("configuration.createsNewApplicationInstance = true"))
    #expect(!source.contains("NSWorkspace.shared.openApplication(at: promptAppURL"))
    #expect(!source.contains("configuration.environment = promptEnvironment"))
    #expect(!source.contains("client.requestInputMonitoringAccess()"))
    #expect(source.contains("try await prepareDaemonRegistrationForPermissionPrompt()"))
    #expect(!source.contains("try requestBundledDaemonInputMonitoringPrompt()"))
    #expect(!source.contains("installTopLevelDaemonPermissionPromptApp"))
    #expect(!source.contains("OpenJoystickDriver Daemon.app"))
    #expect(!source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/ditto\")"))
    #expect(!source.contains("launchDaemonPermissionPromptViaLaunchd"))
    #expect(!source.contains("com.openjoystickdriver.daemon.permission-prompt"))
    #expect(!source.contains("process.executableURL = URL(fileURLWithPath: \"/bin/launchctl\")"))
    #expect(
      source.contains(
        "openInputMonitoringSettings(for: [\"OpenJoystickDriver\"])\n" +
        "    appInputMonitoring = \"\\(await permissionManager.requestAccess())\"\n" +
        "    inputMonitoring = appInputMonitoring\n" +
        "    monitorAppInputMonitoringDecisionInBackground()"
      )
    )
    #expect(source.contains("monitorDaemonInputMonitoringDecisionInBackground()"))
    #expect(!source.contains("appInputMonitoring = await waitForAppInputMonitoringDecision()"))
    #expect(!source.contains("inputMonitoring = await waitForDaemonInputMonitoringDecision()"))
    #expect(source.contains("probeBundledDaemonInputMonitoringState()"))
    #expect(source.contains("for line in output.split(whereSeparator: \\.isNewline).reversed()"))
    #expect(source.contains("\"OJD_PERMISSION_CHECK_ONLY\": \"1\""))
    #expect(source.contains("guard !daemonInstalled else { return }"))
    #expect(source.contains("let task = Task.detached { try DaemonManager.install() }"))
    let promptLaunchRange = source.firstRange(
      of: "try await prepareDaemonRegistrationForPermissionPrompt()"
    )
    let settingsRange = promptLaunchRange.flatMap {
      source.range(
        of: "openInputMonitoringSettings(for: [\"OpenJoystickDriver\"])",
        range: $0.upperBound..<source.endIndex
      )
    }
    let monitorRange = source.firstRange(
      of: "monitorDaemonInputMonitoringDecisionInBackground()"
    )
    let probeRange = source.firstRange(
      of: "inputMonitoring = probeBundledDaemonInputMonitoringState()"
    )
    #expect(promptLaunchRange != nil)
    #expect(settingsRange != nil)
    #expect(probeRange != nil)
    #expect(monitorRange != nil)
    if let promptLaunchRange, let settingsRange, let probeRange, let monitorRange {
      #expect(promptLaunchRange.lowerBound < settingsRange.lowerBound)
      #expect(settingsRange.lowerBound < probeRange.lowerBound)
      #expect(probeRange.lowerBound < monitorRange.lowerBound)
    }
    #expect(source.contains("if inputMonitoring == \"granted\""))
    #expect(source.contains("await recoverDaemonForInputMonitoringRequest()"))
    #expect(
      !source.contains(
        "if daemonConnected {\n      await syncFromDaemonNow()\n    }\n\n" +
        "    if inputMonitoring != \"granted\""
      )
    )
    #expect(source.contains("process.environment = ProcessInfo.processInfo.environment.merging"))
    #expect(!source.contains("\"OJD_PERMISSION_PROMPT_ONLY\": \"1\""))
    #expect(!deviceManager.contains("await permissionManager.requestAccess()"))
    #expect(deviceManager.contains("SDL3 physical input active"))
    #expect(deviceManager.contains("sdlSource.start()"))
    #expect(deviceManager.contains("pollSDL3InputOnce()"))
    #expect(!deviceManager.contains("ensureHIDDetectionState"))
    #expect(!deviceManager.contains("removeHIDPipelines"))
  }

  @Test
  func testDaemonStatusChecksCurrentPermissionState() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let xpcProtocolURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/XPCService+Protocol.swift"
    )
    let source = try String(contentsOf: xpcProtocolURL, encoding: .utf8)

    #expect(source.contains("let inputState = await pm.checkAccess()"))
    #expect(!source.contains("let inputState = await pm.inputMonitoringState"))
  }

  @Test
  func testCompatibilityBackendDoesNotGateOnDaemonInputMonitoring() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let serviceURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/XPCService.swift"
    )
    let protocolURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/XPCService+Protocol.swift"
    )
    let service = try String(contentsOf: serviceURL, encoding: .utf8)
    let xpcProtocol = try String(contentsOf: protocolURL, encoding: .utf8)
    let daemonSource = service + xpcProtocol

    #expect(!service.contains("PermissionManager.currentAccessState()"))
    #expect(!service.contains("Input Monitoring permission required for daemon"))
    #expect(!service.contains("grant OpenJoystickDriver Daemon"))
    #expect(!xpcProtocol.contains("retryUserSpaceBackendAfterPermissionGrant"))
    #expect(!daemonSource.contains("inputState == .granted"))
  }

  @Test
  func testGuiPrefersLiveDaemonPermissionStateOverProbeGrant() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let source = try String(contentsOf: pollingURL, encoding: .utf8)

    #expect(
      source.contains("let probedDaemonInputMonitoring = probeBundledDaemonInputMonitoringState()")
    )
    #expect(source.contains("inputMonitoring = mergeDaemonInputMonitoringStatus"))
    #expect(source.contains("if xpc == \"granted\" || xpc == \"denied\" { return xpc }"))
    #expect(source.contains("if probed == \"granted\" { return probed }"))
  }

  @Test
  func testRuntimeCardsStayLockedUntilPermissionsAreGranted() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let popoverURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift"
    )
    let componentsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarComponents.swift"
    )
    let advancedURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView+AdvancedCards.swift"
    )
    let popover = try String(contentsOf: popoverURL, encoding: .utf8)
    let components = try String(contentsOf: componentsURL, encoding: .utf8)
    let advanced = try String(contentsOf: advancedURL, encoding: .utf8)

    #expect(popover.contains("var permissionsGranted: Bool"))
    #expect(popover.contains("model.appInputMonitoring == \"granted\""))
    #expect(popover.contains("model.inputMonitoring == \"granted\""))
    #expect(popover.contains("PermissionLockedContent(isLocked: !permissionsGranted)"))
    #expect(advanced.contains("PermissionLockedContent(isLocked: !permissionsGranted)"))
    #expect(components.contains("struct PermissionLockedContent<Content: View>: View"))
    #expect(components.contains(".disabled(isLocked)"))
    #expect(components.contains(".grayscale(isLocked ? 1 : 0)"))
    #expect(components.contains(".blur(radius: isLocked ?"))
    #expect(components.contains("Image(systemName: \"lock.fill\")"))
    #expect(components.contains(".allowsHitTesting(!isLocked)"))
  }

  @Test
  func testPermissionUiShowsDaemonInputMonitoringState() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let systemCardsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView+SystemCards.swift"
    )
    let popoverURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift"
    )
    let systemCards = try String(contentsOf: systemCardsURL, encoding: .utf8)
    let popover = try String(contentsOf: popoverURL, encoding: .utf8)

    #expect(systemCards.contains("title: L10n.string(\"app.name\")"))
    #expect(systemCards.contains("permissions.daemonName"))
    #expect(systemCards.contains("requestDaemonInputMonitoringAccess"))
    #expect(systemCards.contains("for: model.inputMonitoring"))
    #expect(systemCards.contains("state: model.inputMonitoring"))
    #expect(popover.contains("requestDaemonInputMonitoringAccess"))
    #expect(popover.contains("readiness.allowDaemonInputMonitoring"))
  }

  @Test
  func testGuiPrefersDaemonCompatibilityStatusUnlessAppFallbackIsOn() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let source = try String(contentsOf: pollingURL, encoding: .utf8)

    #expect(source.contains("visibleCompatibilityStatus(daemonStatus:"))
    #expect(source.contains("daemonStatus.hasPrefix(\"error:\")"))
    #expect(source.contains("bridgeStatus.hasPrefix(\"on\")"))
    #expect(!source.contains("userSpaceVirtualDeviceStatus = compatibilityOutputBridge.status"))
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
