import Foundation
import Testing

struct ScriptPackagingTests {
  @Test
  func testJustfileExposesReleaseParityLocalInstallCommand() throws {
    let justfileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("justfile")
    let justfile = try String(contentsOf: justfileURL, encoding: .utf8)

    #expect(justfile.contains("release-local-install version=\"0.5.0-alpha.7\""))
    #expect(
      justfile.contains(
        "OJD_ENV=release OJD_INSTALL_AFTER_PACKAGE=1 ./scripts/ojd package release \"{{version}}\""
      )
    )
    #expect(!justfile.contains("cp -R .build/debug/OpenJoystickDriver.app /Applications/"))
    #expect(!justfile.contains("rm -rf /Applications/OpenJoystickDriver.app"))
  }

  @Test
  func testBumpVersionSurfacesUseCurrentReleaseVersion() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let bundlesURL = rootURL.appendingPathComponent("scripts/ojd-build-bundles.sh")
    let justfileURL = rootURL.appendingPathComponent("justfile")
    let bumpURL = rootURL.appendingPathComponent("scripts/bump-version.sh")
    let bundles = try String(contentsOf: bundlesURL, encoding: .utf8)
    let justfile = try String(contentsOf: justfileURL, encoding: .utf8)
    let bumpScript = try String(contentsOf: bumpURL, encoding: .utf8)

    #expect(bundles.contains("OJD_BUNDLE_SHORT_VERSION:-0.5.0-alpha.7"))
    #expect(justfile.contains("release-local-install version=\"0.5.0-alpha.7\""))
    #expect(bumpScript.contains("justfile"))
    #expect(bumpScript.contains("ScriptPackagingTests.swift"))
    #expect(bumpScript.contains("ScriptPackagingTests stale version guards"))
    #expect(!bundles.contains("0.5.0-alpha.6"))
    #expect(!justfile.contains("0.5.0-alpha.6"))
  }

  @Test
  func testDmgPackagingUsesNativeFinderStyling() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/ojd-package.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("cp -R \"$app_path\" \"$staging_dir/OpenJoystickDriver.app\""))
    #expect(script.contains("ln -s /Applications \"$staging_dir/Applications\""))
    #expect(!script.contains("ojd-dmg-background.py"))
    #expect(!script.contains("set background picture of viewOptions"))
    #expect(!script.contains("tell application \"Finder\""))
    #expect(!script.contains("osascript"))
  }

  @Test
  func testReleasePackageVerifiesSignedHIDEntitlementsBeforeInstall() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageScriptURL = rootURL.appendingPathComponent("scripts/ojd-package.sh")
    let bundlesScriptURL = rootURL.appendingPathComponent("scripts/ojd-build-bundles.sh")
    let commonScriptURL = rootURL.appendingPathComponent("scripts/ojd-common.sh")
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)
    let bundlesScript = try String(contentsOf: bundlesScriptURL, encoding: .utf8)
    let commonScript = try String(contentsOf: commonScriptURL, encoding: .utf8)
    let releaseScripts = packageScript + "\n" + bundlesScript + "\n" + commonScript

    #expect(packageScript.contains("verify_release_app_entitlements()"))
    #expect(packageScript.contains("verify_release_app_entitlements \"$app_path\""))
    #expect(packageScript.contains("OJD_INSTALL_AFTER_PACKAGE"))
    #expect(packageScript.contains("/usr/bin/ditto \"$source_app\" \"$dest_app\""))
    #expect(releaseScripts.contains("_require_signed_entitlement_value"))
    #expect(packageScript.contains("\"$target_app\""))
    #expect(packageScript.contains("\"$target_daemon\""))
    #expect(releaseScripts.contains("com.apple.developer.hid.virtual.device"))
    #expect(bundlesScript.contains("verify_gui_app_signed_entitlements \"$GUI_APP\""))
    #expect(bundlesScript.contains("verify_daemon_app_signed_entitlements \"$DAEMON_BUNDLE\""))
  }

  @Test
  func testBuildScriptRequiresInstalledSigningIdentity() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let scriptURL = rootURL.appendingPathComponent("scripts/ojd-build.sh")
    let bundlesURL = rootURL.appendingPathComponent("scripts/ojd-build-bundles.sh")
    let commonURL = rootURL.appendingPathComponent("scripts/ojd-common.sh")
    let launchAgentURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
    )
    let script = try String(contentsOf: scriptURL, encoding: .utf8) + "\n"
      + String(contentsOf: bundlesURL, encoding: .utf8) + "\n"
      + String(contentsOf: commonURL, encoding: .utf8)
    let launchAgent = try String(contentsOf: launchAgentURL, encoding: .utf8)
    let packaging = script + "\n" + launchAgent

    #expect(script.contains("security find-identity -v -p codesigning"))
    #expect(script.contains("grep -Fi \"$identity\""))
    #expect(script.contains("_codesign_identity_available \"$GUI_IDENTITY\""))
    #expect(script.contains("_codesign_identity_available \"$DAEMON_IDENTITY\""))
    #expect(script.contains("SWIFT_BIN="))
    #expect(script.contains("\"$SWIFT_BIN\" build"))
    #expect(script.contains("_require_profile_entitlement_value"))
    #expect(script.contains("_require_signed_entitlement_value"))
    #expect(script.contains("codesign\", \"-d\", \"--entitlements\", \"-\", \"--xml\""))
    #expect(
      script.contains("local sign_args=(--sign \"$identity\" --force --generate-entitlement-der)")
    )
    #expect(script.contains("local DEXT_SIGN_ARGS=("))
    #expect(
      script.contains("--generate-entitlement-der\n      --entitlements \"$DEXT_ENTITLEMENTS_TMP\"")
    )
    #expect(script.contains("local APP_SIGN_ARGS=("))
    #expect(
      script.contains("--generate-entitlement-der\n      --entitlements \"$GUI_ENTITLEMENTS\"")
    )
    #expect(!script.contains("DEXT_SIGN_ARGS+=(--generate-entitlement-der"))
    #expect(!script.contains("APP_SIGN_ARGS+=(--generate-entitlement-der"))
    #expect(!script.contains("codesign --sign \"$identity\" --force --generate-entitlement-der"))
    #expect(script.contains("verify_profile_cert \"$GUI_PROFILE\" \"$GUI_IDENTITY\""))
    #expect(script.contains("verify_profile_cert \"$DAEMON_PROFILE\" \"$DAEMON_IDENTITY\""))
    #expect(!script.contains("if [[ \"$OJD_ENV\" == \"release\" ]]; then\n    verify_profile_cert"))
    #expect(script.contains("\"$DAEMON_PROFILE\""))
    #expect(script.contains("\"${DEVELOPMENT_TEAM}.com.openjoystickdriver.daemon\""))
    #expect(script.contains("\"$DAEMON_BUNDLE\""))
    #expect(script.contains("\"com.apple.developer.hid.virtual.device\""))
    #expect(packaging.contains("Contents/Library/LoginItems"))
    #expect(packaging.contains("<key>BundleProgram</key>"))
    #expect(
      packaging.contains(
        "Contents/Library/LoginItems/OpenJoystickDriverDaemon.app/Contents/MacOS/" +
        "OpenJoystickDriverDaemon"
      )
    )
    #expect(!script.contains("cp \"$daemon_bin\" \"$GUI_MACOS/OpenJoystickDriverDaemon\""))
    #expect(script.contains("<string>OpenJoystickDriverDaemon</string>"))
    #expect(script.contains("<key>LSUIElement</key>"))
    #expect(!script.contains("<key>LSBackgroundOnly</key>"))
    #expect(script.contains("<key>NSInputMonitoringUsageDescription</key>"))
    #expect(script.contains("<key>NSAccessibilityUsageDescription</key>"))
    #expect(
      script.contains(
        "OpenJoystickDriver needs Input Monitoring to read controller input and publish " +
          "virtual gamepad events."
      )
    )
    #expect(
      script.contains(
        "OpenJoystickDriverDaemon needs Input Monitoring to read controller input and " +
          "publish virtual gamepad events."
      )
    )
    #expect(script.contains("user-space virtual gamepad events for compatibility mode."))
    #expect(!script.contains("without requiring Accessibility permission"))

    let daemonEntitlementsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/OpenJoystickDriverDaemon.entitlements.template"
    )
    let daemonEntitlements = try String(contentsOf: daemonEntitlementsURL, encoding: .utf8)
    #expect(daemonEntitlements.contains("<key>com.apple.application-identifier</key>"))
    #expect(
      daemonEntitlements.contains(
        "<string>${DEVELOPMENT_TEAM}.com.openjoystickdriver.daemon</string>"
      )
    )
    #expect(daemonEntitlements.contains("<key>com.apple.developer.team-identifier</key>"))
    let guiEntitlementsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/OpenJoystickDriver.entitlements.template"
    )
    let guiEntitlements = try String(contentsOf: guiEntitlementsURL, encoding: .utf8)
    #expect(!guiEntitlements.contains("com.apple.security.app-sandbox"))
    #expect(!daemonEntitlements.contains("com.apple.security.app-sandbox"))
    #expect(!daemonEntitlements.contains("com.apple.security.device.usb"))
  }

  @Test
  func testSparkleReleaseWiringIsPresent() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageURL = rootURL.appendingPathComponent("Package.swift")
    let bundlesURL = rootURL.appendingPathComponent("scripts/ojd-build-bundles.sh")
    let packageScriptURL = rootURL.appendingPathComponent("scripts/ojd-package.sh")
    let dispatcherURL = rootURL.appendingPathComponent("scripts/ojd")
    let workflowURL = rootURL.appendingPathComponent(".github/workflows/release.yml")
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel.swift"
    )
    let xpcOpsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+XPCOperations.swift"
    )
    let package = try String(contentsOf: packageURL, encoding: .utf8)
    let bundles = try String(contentsOf: bundlesURL, encoding: .utf8)
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)
    let dispatcher = try String(contentsOf: dispatcherURL, encoding: .utf8)
    let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let xpcOps = try String(contentsOf: xpcOpsURL, encoding: .utf8)

    #expect(package.contains("https://github.com/sparkle-project/Sparkle"))
    #expect(package.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"))
    #expect(package.contains("@executable_path/../Frameworks"))
    #expect(bundles.contains("SUPublicEDKey"))
    #expect(bundles.contains("SUFeedURL"))
    #expect(bundles.contains("SPARKLE_PUBLIC_ED_KEY"))
    #expect(bundles.contains("SPARKLE_FEED_URL"))
    #expect(bundles.contains("GUI_FRAMEWORKS=\"$GUI_CONTENTS/Frameworks\""))
    #expect(bundles.contains("*.framework"))
    #expect(bundles.contains("$(basename \"$framework\")\" == \"Sparkle.framework\""))
    #expect(bundles.contains("$framework/Versions/B/XPCServices/Installer.xpc"))
    #expect(bundles.contains("$framework/Versions/B/XPCServices/Downloader.xpc"))
    #expect(bundles.contains("$framework/Versions/B/Autoupdate"))
    #expect(bundles.contains("$framework/Versions/B/Updater.app"))
    #expect(bundles.contains("--preserve-metadata=entitlements"))
    #expect(packageScript.contains("bundle_version_from_semver"))
    #expect(packageScript.contains("generate_appcast"))
    #expect(packageScript.contains("--ed-key-file"))
    #expect(packageScript.contains("SPARKLE_ED_PRIVATE_KEY"))
    #expect(dispatcher.contains("appcast)"))
    #expect(workflow.contains("SPARKLE_PUBLIC_ED_KEY"))
    #expect(workflow.contains("SPARKLE_ED_PRIVATE_KEY"))
    #expect(workflow.contains("package appcast"))
    #expect(workflow.contains("appcast.xml"))
    #expect(workflow.contains("if: ${{ env.SPARKLE_ED_PRIVATE_KEY != '' }}"))
    #expect(appModel.contains("SparkleUpdateController"))
    #expect(appModel.contains("repairDaemonForCurrentAppVersionIfNeeded"))
    #expect(xpcOps.contains("sparkleUpdates.checkForUpdates"))
  }


  @Test
  func testSparkleUpdateErrorsAreExplicitlyMapped() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let controllerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/SparkleUpdateController.swift"
    )
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel.swift"
    )
    let controller = try String(contentsOf: controllerURL, encoding: .utf8)
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)

    #expect(controller.contains("checkForUpdateInformation()"))
    #expect(controller.contains("didFinishUpdateCycleFor updateCheck"))
    #expect(controller.contains("SPUNoUpdateFoundReason"))
    #expect(controller.contains("SUInvalidFeedURLError"))
    #expect(controller.contains("SUAppcastParseError"))
    #expect(controller.contains("SUSignatureError"))
    #expect(controller.contains("SURunningFromDiskImageError"))
    #expect(controller.contains("NSURLErrorNotConnectedToInternet"))
    #expect(controller.contains("TLS validation failed for update feed"))
    #expect(controller.contains("Move OpenJoystickDriver.app into /Applications"))
    #expect(appModel.contains("lazy var sparkleUpdates = SparkleUpdateController"))
    #expect(appModel.contains("self?.updateCheckState = state"))
  }

  @Test
  func testNotarizeSubmitPrintsNotarytoolFailures() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let notarizeURL = rootURL.appendingPathComponent("scripts/ojd-notarize.sh")
    let script = try String(contentsOf: notarizeURL, encoding: .utf8)

    #expect(
      script.contains(
        "if ! SUBMIT_OUTPUT=$(xcrun notarytool submit \"$ZIP_PATH\" \\\n" +
          "  \"${AUTH_ARGS[@]}\" 2>&1); then"
      )
    )
    #expect(script.contains("echo \"$SUBMIT_OUTPUT\""))
    #expect(script.contains("ERROR: notarytool submit failed before a submission ID was issued"))
  }

  @Test
  func testReleaseWorkflowPreflightsNotarizationCredentials() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let workflowURL = rootURL.appendingPathComponent(".github/workflows/release.yml")
    let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

    #expect(workflow.contains("- name: Validate notarization credentials"))
    #expect(workflow.contains("./scripts/ojd notarize history"))
    guard
      let preflightRange = workflow.range(of: "Validate notarization credentials"),
      let packageRange = workflow.range(of: "Package release build")
    else {
      Issue.record("Expected release workflow preflight before package step")
      return
    }

    #expect(preflightRange.lowerBound < packageRange.lowerBound)
  }

  @Test
  func testNotarizeHistoryDoesNotRequireBuiltAppBundle() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let notarizeURL = rootURL.appendingPathComponent("scripts/ojd-notarize.sh")
    let script = try String(contentsOf: notarizeURL, encoding: .utf8)

    guard
      let historyRange = script.range(of: "if [[ \"$subcmd\" == \"history\" ]]; then"),
      let appCheckRange = script.range(of: "if [[ ! -d \"$APP\" ]]; then")
    else {
      Issue.record("Expected notarize history and app bundle existence check blocks")
      return
    }

    #expect(historyRange.lowerBound < appCheckRange.lowerBound)
  }

  @Test
  func testInputMonitoringRequestUsesDaemonOwnedPrompt() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel+InputMonitoring.swift"
    )
    let daemonMainURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/main.swift"
    )
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let daemonMain = try String(contentsOf: daemonMainURL, encoding: .utf8)

    #expect(appModel.contains("LSRegisterURL(appURL as CFURL, true)"))
    #expect(
      appModel.contains("registerApplicationBundleForPermissionPrompt(Bundle.main.bundleURL)")
    )
    #expect(appModel.contains("try await requestDaemonOwnedInputMonitoringPrompt()"))
    #expect(appModel.contains("try await client.requestInputMonitoringAccess()"))
    #expect(appModel.contains("try requestBundledDaemonInputMonitoringPrompt()"))
    #expect(appModel.contains("PermissionManager.requestAccessibilityAccess(prompt: true)"))
    #expect(appModel.contains("registerApplicationBundleForPermissionPrompt(daemonAppURL)"))
    #expect(!appModel.contains("installTopLevelDaemonPermissionPromptApp"))
    #expect(!appModel.contains("OpenJoystickDriver Daemon.app"))
    #expect(!appModel.contains("NSWorkspace.shared.openApplication(at: promptAppURL"))
    #expect(!appModel.contains("configuration.createsNewApplicationInstance = true"))
    #expect(!appModel.contains("configuration.activates = true"))
    #expect(appModel.contains("process.arguments = [\"--request-input-monitoring\"]"))
    #expect(appModel.contains("\"OJD_PERMISSION_PROMPT_ONLY\": \"1\""))
    #expect(appModel.contains("openInputMonitoringSettings(for: [\"OpenJoystickDriverDaemon\"])"))
    #expect(!appModel.contains("inputMonitoring = appInputMonitoring"))
    #expect(daemonMain.contains("NSApp.setActivationPolicy(.accessory)"))
    #expect(daemonMain.contains("NSApp.activate(ignoringOtherApps: true)"))
    #expect(daemonMain.contains("OJD_PERMISSION_PROMPT_ONLY"))
    #expect(daemonMain.contains("--request-input-monitoring"))
    #expect(daemonMain.contains("Requesting Accessibility access for daemon"))
  }

  @Test
  func testBackendDiagnosticsConfigureConsumerSpecificRoutes() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let diagnoseURL = rootURL.appendingPathComponent("scripts/ojd-diagnose.sh")
    let probeURL = rootURL.appendingPathComponent("tools/sdl3-gamepad-probe/main.c")
    let diagnose = try String(contentsOf: diagnoseURL, encoding: .utf8)
    let probe = try String(contentsOf: probeURL, encoding: .utf8)

    #expect(diagnose.contains("SDL3 HIDAPI Xbox 360 consumer probe"))
    #expect(diagnose.contains("sdl3-hidapi-x360 --seconds \"$seconds\""))
    #expect(
      diagnose.contains(
        "sdl3-gamecontroller --seconds \"$seconds\" "
          + "--expect-single-neutral-gamepad --neutral-axis-tolerance 1"
      )
    )
    #expect(!diagnose.contains("SDL_JOYSTICK_IOKIT=0 \\\n    SDL_JOYSTICK_HIDAPI=0"))
    #expect(diagnose.contains("restore_ojd_route"))
    #expect(diagnose.contains("restore_ojd_route \"${initial_identity:-}\""))
    #expect(!diagnose.contains("\"$0\" gamecontroller --seconds \"$seconds\" || true"))
    #expect(probe.contains("--expect-single-neutral-gamepad"))
    #expect(probe.contains("--neutral-axis-tolerance"))
    #expect(probe.contains("abs((int)value) > neutral_axis_tolerance"))
    #expect(probe.contains("check_single_neutral_gamepad"))
    #expect(probe.contains("OpenJoystickDriver-UserSpace:"))
    #expect(probe.contains("03008d62869800002400000000006800"))
    #expect(probe.contains("!is_ojd_guid(guid_str) && !has_ojd_serial(id)"))
  }

  @Test
  func testGameControllerDiagnosticsCanInjectSelfTest() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let diagnoseURL = rootURL.appendingPathComponent("scripts/ojd-diagnose.sh")
    let diagnose = try String(contentsOf: diagnoseURL, encoding: .utf8)

    #expect(diagnose.contains("inject_selftest=\"0\""))
    #expect(diagnose.contains("--inject-selftest"))
    #expect(diagnose.contains("args+=(--inject-selftest)"))
    #expect(diagnose.contains("args+=(--inject-delay-ms \"$inject_delay_ms\")"))
    #expect(diagnose.contains("args+=(--inject-seconds \"$inject_seconds\")"))
  }

  @Test
  func testBackendDiagnosticsReturnFailureWhenCriticalChecksFail() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let diagnoseURL = rootURL.appendingPathComponent("scripts/ojd-diagnose.sh")
    let diagnose = try String(contentsOf: diagnoseURL, encoding: .utf8)

    #expect(diagnose.contains("local backend_failures=0"))
    #expect(diagnose.contains("backend_failures=$((backend_failures + 1))"))
    #expect(diagnose.contains("return \"$backend_failures\""))
    #expect(
      !diagnose.contains("run_limited \"$step_timeout\" /usr/bin/env bash \"$0\" dext || true")
    )
    #expect(!diagnose.contains("--expect-single-neutral-ojd || true"))
    #expect(!diagnose.contains("--neutral-axis-tolerance 1 || true"))
    #expect(diagnose.contains("run_backend_acceptance_loop \"$seconds\""))
    #expect(!diagnose.contains("run_backend_acceptance_loop \"$seconds\"\n  exit 0"))
  }

  @Test
  func testStaleDextRepairReportsNonInteractiveSudoBlocker() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let repairURL = rootURL.appendingPathComponent("scripts/ojd-repair-stale-dext.sh")
    let script = try String(contentsOf: repairURL, encoding: .utf8)

    #expect(script.contains("kill_stale_dext_process()"))
    #expect(script.contains("if [[ -t 0 && -t 1 ]]; then"))
    #expect(script.contains("sudo kill -9 \"$pid\""))
    #expect(script.contains("sudo -n kill -9 \"$pid\""))
    #expect(script.contains("requires administrator approval"))
    #expect(script.contains("reboot to let macOS unload the stale DriverKit process"))
  }

  @Test
  func testForegroundConsumerMonitorKeepsUnbundledConsumersObservable() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let monitorURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor.swift"
    )
    let monitor = try String(contentsOf: monitorURL, encoding: .utf8)

    #expect(monitor.contains("return path"))
  }

  @Test
  func testForegroundConsumerMonitorReusesHIDManagerDuringPolling() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let monitorURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor.swift"
    )
    let monitor = try String(contentsOf: monitorURL, encoding: .utf8)

    #expect(monitor.contains("private static let virtualDeviceManager"))
    #expect(monitor.contains("IOHIDManagerCopyDevices(virtualDeviceManager)"))
    #expect(!monitor.contains("defer { IOHIDManagerClose(manager"))
  }

  @Test
  func testForegroundConsumerMonitorSerializesSharedHIDManagerAccess() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let monitorURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor.swift"
    )
    let monitor = try String(contentsOf: monitorURL, encoding: .utf8)

    #expect(monitor.contains("private static let virtualDeviceManagerLock = NSLock()"))
    #expect(monitor.contains("virtualDeviceManagerLock.withLock"))
    #expect(monitor.contains("IOHIDManagerCopyDevices(virtualDeviceManager)"))
  }

  @Test
  func testForegroundConsumerMonitorCachesFrontmostBundleFromActivationNotifications() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let monitorURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor.swift"
    )
    let monitor = try String(contentsOf: monitorURL, encoding: .utf8)

    #expect(monitor.contains("cachedFrontmostBundleRoot"))
    #expect(monitor.contains("NSWorkspace.applicationUserInfoKey"))
    #expect(monitor.contains("frontmostBundleRootPathFromCache()"))
    #expect(!monitor.contains("let frontmostBundleRoot = await MainActor.run"))
  }

  @Test
  func testRebuildFastQuitsRunningGuiBeforeReplacingInstalledApp() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let buildScriptURL = rootURL.appendingPathComponent("scripts/ojd-build.sh")
    let script = try String(contentsOf: buildScriptURL, encoding: .utf8)

    #expect(script.contains("quit_running_gui_app()"))
    #expect(script.contains("quit_running_gui_app\n  rm -rf \"$APP_DST\""))
    #expect(
      script.contains(
        "/usr/bin/osascript -e 'tell application id \"com.openjoystickdriver\" to quit'"
      )
    )
    #expect(script.contains("killall OpenJoystickDriver"))
  }

  @Test
  func testLaunchAgentUsesBundleProgramAndModernServiceManagement() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let launchAgentURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/com.openjoystickdriver.daemon.plist"
    )
    let daemonManagerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Daemon/DaemonManager.swift"
    )
    let bundlesScriptURL = rootURL.appendingPathComponent("scripts/ojd-build-bundles.sh")

    let launchAgent = try String(contentsOf: launchAgentURL, encoding: .utf8)
    let daemonManager = try String(contentsOf: daemonManagerURL, encoding: .utf8)
    let bundlesScript = try String(contentsOf: bundlesScriptURL, encoding: .utf8)

    #expect(launchAgent.contains("<key>BundleProgram</key>"))
    #expect(
      launchAgent.contains(
        "Contents/Library/LoginItems/OpenJoystickDriverDaemon.app/Contents/MacOS/"
          + "OpenJoystickDriverDaemon"
      )
    )
    #expect(!launchAgent.contains("<key>ProgramArguments</key>"))
    #expect(
      bundlesScript.contains(
        "cp \"$LAUNCHAGENTS_SRC\" "
          + "\"$LAUNCHAGENTS_DST/com.openjoystickdriver.daemon.plist\""
      )
    )
    #expect(daemonManager.contains("SMAppService.agent(plistName: agentPlistName)"))
    #expect(daemonManager.contains("try appService.register()"))
  }

}
