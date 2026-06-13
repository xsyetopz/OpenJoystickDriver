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
    #expect(daemonMain.contains("Requesting Accessibility access for daemon"))
    #expect(daemonMain.contains("PermissionManager.requestAccessibilityAccess(prompt: true)"))
    #expect(daemonMain.contains("Permission approval pending for daemon helper app"))
    #expect(daemonMain.contains("PermissionManager.currentAccessibilityState()"))
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
  func testGuiRequestsDaemonOwnedPermissionForDaemonBackend() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let deviceManagerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager.swift"
    )
    let source = try String(contentsOf: inputMonitoringURL, encoding: .utf8)
    let deviceManager = try String(contentsOf: deviceManagerURL, encoding: .utf8)

    #expect(source.contains("try await requestDaemonOwnedInputMonitoringPrompt()"))
    #expect(source.contains("try await client.requestInputMonitoringAccess()"))
    #expect(source.contains("try requestBundledDaemonInputMonitoringPrompt()"))
    #expect(source.contains("process.arguments = [\"--request-input-monitoring\"]"))
    #expect(source.contains("OJD_PERMISSION_PROMPT_ONLY"))
    #expect(source.contains("try await prepareDaemonRegistrationForPermissionPrompt()"))
    #expect(!source.contains("installTopLevelDaemonPermissionPromptApp"))
    #expect(!source.contains("OpenJoystickDriver Daemon.app"))
    #expect(!source.contains("process.executableURL = URL(fileURLWithPath: \"/usr/bin/ditto\")"))
    #expect(!source.contains("launchDaemonPermissionPromptViaLaunchd"))
    #expect(!source.contains("com.openjoystickdriver.daemon.permission-prompt"))
    #expect(!source.contains("process.executableURL = URL(fileURLWithPath: \"/bin/launchctl\")"))
    #expect(source.contains("openInputMonitoringSettings(for: [\"OpenJoystickDriverDaemon\"])"))
    #expect(!source.contains("inputMonitoring = appInputMonitoring"))
    #expect(source.contains("monitorDaemonInputMonitoringDecisionInBackground()"))
    #expect(!source.contains("appInputMonitoring = await waitForAppInputMonitoringDecision()"))
    #expect(!source.contains("inputMonitoring = await waitForDaemonInputMonitoringDecision()"))
    #expect(source.contains("probeBundledDaemonInputMonitoringState()"))
    #expect(source.contains("PermissionManager.requestAccessibilityAccess(prompt: true)"))
    #expect(source.contains("for line in output.split(whereSeparator: \\.isNewline).reversed()"))
    #expect(source.contains("\"OJD_PERMISSION_CHECK_ONLY\": \"1\""))
    #expect(source.contains("guard !daemonInstalled else { return }"))
    #expect(
      source.contains("try await runDaemonLifecycleOperation { try DaemonManager.install() }")
    )
    let promptLaunchRange = source.firstRange(
      of: "try await prepareDaemonRegistrationForPermissionPrompt()"
    )
    let settingsRange = promptLaunchRange.flatMap {
      source.range(
        of: "openInputMonitoringSettings(for: [\"OpenJoystickDriverDaemon\"])",
        range: $0.upperBound..<source.endIndex
      )
    }
    let daemonRequestRange = promptLaunchRange.flatMap {
      source.range(
        of: "try await requestDaemonOwnedInputMonitoringPrompt()",
        range: $0.upperBound..<source.endIndex
      )
    }
    let monitorRange = source.firstRange(
      of: "monitorDaemonInputMonitoringDecisionInBackground()"
    )
    let probeRange = source.firstRange(
      of: "inputMonitoring = await probeBundledDaemonInputMonitoringState()"
    )
    #expect(promptLaunchRange != nil)
    #expect(settingsRange != nil)
    #expect(daemonRequestRange != nil)
    #expect(probeRange != nil)
    #expect(monitorRange != nil)
    if let promptLaunchRange, let settingsRange, let daemonRequestRange, let probeRange,
      let monitorRange
    {
      #expect(promptLaunchRange.lowerBound < settingsRange.lowerBound)
      #expect(settingsRange.lowerBound < daemonRequestRange.lowerBound)
      #expect(daemonRequestRange.lowerBound < probeRange.lowerBound)
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
    #expect(!deviceManager.contains("await permissionManager.requestAccess()"))
    #expect(deviceManager.contains("dual detection active"))
    #expect(deviceManager.contains("runUSBDetection()"))
    #expect(deviceManager.contains("ensureHIDDetectionState"))
    #expect(deviceManager.contains("removeHIDPipelines"))
    #expect(!deviceManager.contains("await permissionManager.requestAccess()"))
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
      source.contains(
        "let probedDaemonInputMonitoring = await probeBundledDaemonInputMonitoringState()"
      )
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
  func testPermissionUiSeparatesInputMonitoringAndAccessibility() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel.swift"
    )
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let systemCardsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView+SystemCards.swift"
    )
    let popoverURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift"
    )
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let polling = try String(contentsOf: pollingURL, encoding: .utf8)
    let systemCards = try String(contentsOf: systemCardsURL, encoding: .utf8)
    let popover = try String(contentsOf: popoverURL, encoding: .utf8)

    #expect(appModel.contains("@Published var daemonAccessibility = \"unknown\""))
    #expect(appModel.contains("var compatibilityRequiresAccessibility: Bool"))
    #expect(appModel.contains("var compatibilityAccessibilityGranted: Bool"))
    #expect(polling.contains("daemonAccessibility = status.accessibility ?? \"unknown\""))
    #expect(systemCards.contains("L10n.string(\"permissions.groupInputMonitoring\")"))
    #expect(systemCards.contains("L10n.string(\"permissions.groupAccessibility\")"))
    #expect(systemCards.contains("state: model.daemonAccessibility"))
    #expect(systemCards.contains("requestCompatibilityAccessibilityAccess"))
    #expect(systemCards.contains("for: model.daemonAccessibility"))
    #expect(systemCards.contains("permission: L10n.string(\"permissions.groupAccessibility\")"))
    #expect(!systemCards.contains("Text(\"Input Monitoring\")"))
    #expect(!systemCards.contains("Text(\"Accessibility\")"))
    #expect(!systemCards.contains("return \"Open System Settings"))
    #expect(!systemCards.contains("return \"Request access"))
    #expect(popover.contains("model.compatibilityAccessibilityGranted"))
    #expect(popover.contains("L10n.string(\"readiness.allowDaemonAccessibility\")"))
    #expect(!popover.contains("Allow Accessibility for OpenJoystickDriverDaemon."))
  }

  @Test
  func testPermissionAccessibilityStringsExistInEveryLocalization() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let resourcesURL = rootURL.appendingPathComponent("Sources/OpenJoystickDriverKit/Resources")
    let templateURL = resourcesURL.appendingPathComponent(
      "Localization/Localizable.template.strings"
    )
    let requiredKeys = [
      "readiness.allowDaemonAccessibility",
      "permissions.groupInputMonitoring",
      "permissions.groupAccessibility",
      "permissions.openSettingsForPermission",
      "permissions.requestAccessForPermission",
    ]
    let template = try String(contentsOf: templateURL, encoding: .utf8)
    for key in requiredKeys {
      #expect(template.contains("\"\(key)\" ="))
    }

    let localizations = try FileManager.default.contentsOfDirectory(
      at: resourcesURL,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "lproj" }

    for localization in localizations {
      let stringsURL = localization.appendingPathComponent("Localizable.strings")
      let strings = try String(contentsOf: stringsURL, encoding: .utf8)
      for key in requiredKeys {
        #expect(
          strings.contains("\"\(key)\" ="),
          "\(localization.lastPathComponent) missing \(key)"
        )
      }
    }
  }

  @Test
  func testCompatibilityAccessibilityErrorShowsRequestAction() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel.swift"
    )
    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let popoverURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift"
    )
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let inputMonitoring = try String(contentsOf: inputMonitoringURL, encoding: .utf8)
    let popover = try String(contentsOf: popoverURL, encoding: .utf8)

    #expect(appModel.contains("needsVirtualHIDAccessibility"))
    #expect(inputMonitoring.contains("requestCompatibilityAccessibilityAccess"))
    #expect(inputMonitoring.contains("Privacy_Accessibility"))
    #expect(popover.contains("model.compatibilityAccessibilityGranted"))
    #expect(popover.contains("requestCompatibilityAccessibilityAccess"))
  }

  @Test
  func testHeadlessStatusPrintsAccessibilityPermissionState() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let statusURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Commands/StatusCommand.swift"
    )
    let diagnoseURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Commands/DiagnoseCommand.swift"
    )
    let status = try String(contentsOf: statusURL, encoding: .utf8)
    let diagnose = try String(contentsOf: diagnoseURL, encoding: .utf8)

    #expect(status.contains("Accessibility   : "))
    #expect(status.contains("PermissionManager.currentAccessibilityState()"))
    #expect(status.contains("Privacy > Accessibility"))
    #expect(diagnose.contains("Accessibility   : "))
    #expect(diagnose.contains("PermissionManager.currentAccessibilityState()"))
    #expect(diagnose.contains("Grant Accessibility"))
  }

  @Test
  func testHeadlessPermissionsCommandRequestsDaemonOwnedPrompt() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cliURL = rootURL.appendingPathComponent("Sources/OpenJoystickDriver/CLI.swift")
    let permissionsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Commands/PermissionsCommand.swift"
    )
    let cli = try String(contentsOf: cliURL, encoding: .utf8)
    let permissions = try String(contentsOf: permissionsURL, encoding: .utf8)

    #expect(cli.contains("case \"permissions\": PermissionsCommand().run"))
    #expect(cli.contains("permissions Request macOS Input Monitoring/Accessibility prompts"))
    #expect(permissions.contains("request-daemon"))
    #expect(permissions.contains("DaemonManager.bundledDaemonApplicationURL"))
    #expect(permissions.contains("DaemonManager.daemonExecutableURL"))
    #expect(permissions.contains("LSRegisterURL(daemonAppURL as CFURL, true)"))
    #expect(permissions.contains("process.arguments = [\"--request-input-monitoring\"]"))
    #expect(permissions.contains("\"OJD_PERMISSION_PROMPT_ONLY\": \"1\""))
    #expect(permissions.contains("Privacy_ListenEvent"))
    #expect(permissions.contains("Privacy_Accessibility"))
    #expect(permissions.contains("OpenJoystickDriverDaemon"))
  }

  @Test
  func testUninstallConfirmationDismissesBeforeAsyncUnregister() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let popoverURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView.swift"
    )
    let lifecycleURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+DaemonLifecycle.swift"
    )
    let popover = try String(contentsOf: popoverURL, encoding: .utf8)
    let lifecycle = try String(contentsOf: lifecycleURL, encoding: .utf8)

    #expect(popover.contains("showUninstallConfirm = false\n          Task {"))
    #expect(
      lifecycle.contains(
        "func uninstallDaemon() async {\n    daemonError = nil\n    daemonRestarting = true"
      )
    )
    #expect(lifecycle.contains("defer { daemonRestarting = false }"))
  }

  @Test
  func testDaemonLifecycleOperationsHaveTimeouts() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let lifecycleURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+DaemonLifecycle.swift"
    )
    let lifecycle = try String(contentsOf: lifecycleURL, encoding: .utf8)

    #expect(lifecycle.contains("daemonLifecycleTimeoutNanoseconds"))
    #expect(lifecycle.contains("withCheckedThrowingContinuation"))
    #expect(lifecycle.contains("DaemonLifecycleCompletionBox"))
    #expect(lifecycle.contains("try await runDaemonLifecycleOperation"))
    #expect(lifecycle.contains("Daemon operation timed out."))

    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let inputMonitoring = try String(contentsOf: inputMonitoringURL, encoding: .utf8)
    #expect(inputMonitoring.contains("try await runDaemonLifecycleOperation"))
    #expect(!inputMonitoring.contains("let task = Task.detached"))
  }

  @Test
  func testDaemonPermissionProbeDoesNotBlockMainActorPolling() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let inputMonitoringURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let polling = try String(contentsOf: pollingURL, encoding: .utf8)
    let inputMonitoring = try String(contentsOf: inputMonitoringURL, encoding: .utf8)

    #expect(
      polling.contains(
        "let probedDaemonInputMonitoring = await probeBundledDaemonInputMonitoringState()"
      )
    )
    #expect(
      inputMonitoring.contains("func probeBundledDaemonInputMonitoringState() async -> String")
    )
    #expect(inputMonitoring.contains("Task.detached"))
    #expect(inputMonitoring.contains("func probeBundledDaemonInputMonitoringStateNow() -> String"))
    #expect(inputMonitoring.contains("process.waitUntilExit()"))
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
  func testGuiAppOwnedCompatibilityBridgeOnlyRunsAsDaemonErrorFallback() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let source = try String(contentsOf: pollingURL, encoding: .utf8)

    #expect(source.contains("daemonUserSpaceVirtualDeviceStatus"))
    #expect(source.contains("isAppOwnedCompatibilityOutputActive(daemonStatus:"))
    #expect(source.contains("daemonStatus.hasPrefix(\"error:\")"))
    #expect(source.contains("compatibilityOutputBridge.stop()"))
  }

  @Test
  func testGuiCompatibilityBridgeDoesNotWakeAtInputRateWhenFallbackInactive() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pollingURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+Polling.swift"
    )
    let source = try String(contentsOf: pollingURL, encoding: .utf8)

    #expect(source.contains("compatibilityOutputBridgeFastPollNanoseconds"))
    #expect(source.contains("compatibilityOutputBridgePollNanoseconds()"))
    #expect(
      source.contains(
        "isAppOwnedCompatibilityOutputActive(daemonStatus: daemonUserSpaceVirtualDeviceStatus)"
      )
    )
    #expect(source.contains("return compatibilityOutputBridgeFastPollNanoseconds"))
    #expect(source.contains("return appModelPollNanoseconds"))
    #expect(
      source.contains(
        "try? await Task.sleep(nanoseconds: self.compatibilityOutputBridgePollNanoseconds())"
      )
    )
  }

  @Test
  func testGuiDeviceIdentityIncludesSerialOrLocationToAvoidDuplicateRows() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel.swift"
    )
    let xpcPayloadsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/XPC/XPCPayloads.swift"
    )
    let deviceManagerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Device/DeviceManager.swift"
    )
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let xpcPayloads = try String(contentsOf: xpcPayloadsURL, encoding: .utf8)
    let deviceManager = try String(contentsOf: deviceManagerURL, encoding: .utf8)

    #expect(xpcPayloads.contains("public let locationID: UInt32?"))
    #expect(xpcPayloads.contains("case locationID"))
    #expect(deviceManager.contains("locationID: id.locationID"))
    #expect(appModel.contains("let locationID: UInt32?"))
    #expect(appModel.contains("self.locationID = description.locationID"))
    #expect(appModel.contains("description.serialNumber ?? description.locationID.map"))
    #expect(
      !appModel.contains(
        "self.id = \"\\(description.vendorID):\\(description.productID):\\(description.name)\""
      )
    )
  }

  @Test
  func testGuiQueriesSelectedControllerBySerialOrLocation() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let xpcProtocolURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/XPC/XPCProtocol.swift"
    )
    let xpcClientURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/XPC/XPCClient.swift"
    )
    let xpcServiceURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/XPCService+Protocol.swift"
    )
    let inputWindowURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView.swift"
    )
    let rumbleURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/Views/InputTestWindowView+Rumble.swift"
    )
    let appOperationsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+XPCOperations.swift"
    )
    let xpcProtocol = try String(contentsOf: xpcProtocolURL, encoding: .utf8)
    let xpcClient = try String(contentsOf: xpcClientURL, encoding: .utf8)
    let xpcService = try String(contentsOf: xpcServiceURL, encoding: .utf8)
    let inputWindow = try String(contentsOf: inputWindowURL, encoding: .utf8)
    let rumble = try String(contentsOf: rumbleURL, encoding: .utf8)
    let appOperations = try String(contentsOf: appOperationsURL, encoding: .utf8)

    #expect(xpcProtocol.contains("serialNumber: String?"))
    #expect(xpcProtocol.contains("locationID: Int"))
    #expect(xpcClient.contains("public func deviceInputState("))
    #expect(xpcClient.contains("public func packetLog("))
    #expect(xpcClient.contains("public func sendPhysicalRumble("))
    #expect(xpcClient.contains("serialNumber: serialNumber,"))
    #expect(xpcClient.contains("locationID: locationID.map(Int.init) ?? -1"))
    #expect(xpcService.contains("serialNumber: serialNumber,"))
    #expect(xpcService.contains("locationID: UInt32(optionalXPCID: locationID)"))
    #expect(inputWindow.contains("serialNumber: device.serialNumber"))
    #expect(inputWindow.contains("locationID: device.locationID"))
    #expect(rumble.contains("serialNumber: device.serialNumber"))
    #expect(rumble.contains("locationID: device.locationID"))
    #expect(appOperations.contains("serialNumber: String?"))
    #expect(appOperations.contains("locationID: UInt32?"))
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
