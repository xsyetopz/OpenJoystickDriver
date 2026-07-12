import Foundation
import Testing

struct ScriptPackagingTests {
  @Test
  func testJustfileExposesReleaseParityLocalInstallCommand() throws {
    let justfileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("justfile")
    let justfile = try String(contentsOf: justfileURL, encoding: .utf8)

    #expect(justfile.contains("release-local-install version=\"0.5.0-alpha.5\""))
    #expect(justfile.contains("OJD_ENV=release ./scripts/ojd package release \"{{version}}\""))
    #expect(justfile.contains("cp -R .build/debug/OpenJoystickDriver.app /Applications/"))
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

    #expect(bundles.contains("OJD_BUNDLE_SHORT_VERSION:-0.5.0-alpha.5"))
    #expect(justfile.contains("release-local-install version=\"0.5.0-alpha.5\""))
    #expect(bumpScript.contains("justfile"))
    #expect(!bundles.contains("0.5.0-alpha.3"))
    #expect(!justfile.contains("0.5.0-alpha.3"))
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
    #expect(script.contains("<string>OpenJoystickDriver Daemon</string>"))
    #expect(script.contains("<key>LSUIElement</key>"))
    #expect(!script.contains("<key>LSBackgroundOnly</key>"))
    #expect(script.contains("<key>NSInputMonitoringUsageDescription</key>"))
    #expect(
      script.contains(
        "OpenJoystickDriver needs Input Monitoring to read controller input and publish " +
          "virtual gamepad events."
      )
    )
    #expect(
      script.contains(
        "OpenJoystickDriver Daemon needs Input Monitoring to read controller input and " +
          "publish virtual gamepad events."
      )
    )

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
  func testInputMonitoringRequestUsesNativeAppRegistration() throws {
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
    #expect(appModel.contains("registerApplicationBundleForPermissionPrompt(daemonAppURL)"))
    #expect(appModel.contains("configuration.createsNewApplicationInstance = true"))
    #expect(appModel.contains("configuration.activates = true"))
    #expect(appModel.contains("configuration.arguments = [\"--request-input-monitoring\"]"))
    #expect(daemonMain.contains("NSApp.setActivationPolicy(.accessory)"))
    #expect(daemonMain.contains("NSApp.activate(ignoringOtherApps: true)"))
    #expect(daemonMain.contains("OJD_PERMISSION_PROMPT_ONLY"))
    #expect(daemonMain.contains("--request-input-monitoring"))
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
