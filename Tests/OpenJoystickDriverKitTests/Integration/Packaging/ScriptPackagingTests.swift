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
    let bundlesURL = rootURL.appendingPathComponent("scripts/build-tools/bundles.sh")
    let justfileURL = rootURL.appendingPathComponent("justfile")
    let bumpURL = rootURL.appendingPathComponent("scripts/release/bump-version.sh")
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
      .appendingPathComponent("scripts/release/package.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("cp -R \"$app_path\" \"$staging_dir/OpenJoystickDriver.app\""))
    #expect(script.contains("ln -s /Applications \"$staging_dir/Applications\""))
    #expect(!script.contains("ojd-dmg-background.py"))
    #expect(!script.contains("set background picture of viewOptions"))
    #expect(!script.contains("tell application \"Finder\""))
    #expect(!script.contains("osascript"))
    #expect(script.contains("trap cleanup_dmg_workdirs EXIT"))
    #expect(script.contains("trap - EXIT"))
  }

  @Test
  func testBuildScriptPackagesOneSignedApplicationIdentity() throws {
    let root = try RepositoryRoot.from()
    let bundles = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/bundles.sh"),
      encoding: .utf8
    )
    #expect(bundles.contains("security find-identity -v -p codesigning"))
    #expect(bundles.contains("_require_codesign_identity"))
    #expect(bundles.contains(#""com.apple.developer.hid.virtual.device""#))
    #expect(bundles.contains(#"codesign --force --sign "$GUI_IDENTITY""#))
    #expect(!bundles.contains("DAEMON_IDENTITY"))
    #expect(!bundles.contains("DAEMON_PROFILE"))
    #expect(!bundles.contains("OpenJoystickDriverDaemon"))
    #expect(!bundles.contains("Contents/Library/LoginItems"))
    #expect(!bundles.contains("Contents/Library/LaunchAgents"))
    #expect(!bundles.contains("com.openjoystickdriver.service.plist"))
  }

  @Test
  func testSwiftLintRunsStrictlyWithoutSuppressionBaseline() throws {
    let root = try RepositoryRoot.from()
    let buildScript = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/build.sh"),
      encoding: .utf8
    )

    #expect(buildScript.contains("swiftlint lint --no-cache --strict"))
    #expect(!buildScript.contains("--baseline"))
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent(".swiftlint-baseline.json").path
    ))
  }

  @Test
  func testSparkleReleaseWiringIsPresent() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageURL = rootURL.appendingPathComponent("Package.swift")
    let bundlesURL = rootURL.appendingPathComponent("scripts/build-tools/bundles.sh")
    let packageScriptURL = rootURL.appendingPathComponent("scripts/release/package.sh")
    let dispatcherURL = rootURL.appendingPathComponent("scripts/ojd")
    let workflowURL = rootURL.appendingPathComponent(".github/workflows/release.yml")
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift"
    )
    let serviceOpsURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel/ApplicationServiceOperations.swift"
    )
    let package = try String(contentsOf: packageURL, encoding: .utf8)
    let bundles = try String(contentsOf: bundlesURL, encoding: .utf8)
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)
    let dispatcher = try String(contentsOf: dispatcherURL, encoding: .utf8)
    let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
    let appModel = try String(contentsOf: appModelURL, encoding: .utf8)
    let serviceOps = try String(contentsOf: serviceOpsURL, encoding: .utf8)

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
    #expect(appModel.contains("registerMainAppForLoginIfNeeded"))
    #expect(serviceOps.contains("sparkleUpdates.checkForUpdates"))
  }


  @Test
  func testSparkleUpdateErrorsAreExplicitlyMapped() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let controllerURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/SparkleUpdateController.swift"
    )
    let appModelURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift"
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
  func testInputMonitoringRequestUsesMainApplicationIdentity() throws {
    let root = try RepositoryRoot.from()
    let appModel = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/App/AppModel/InputMonitoring.swift"
      ),
      encoding: .utf8
    )

    #expect(appModel.contains("permissionManager.requestRequiredAccess()"))
    #expect(!appModel.contains("registerApplicationBundleForPermissionPrompt"))
    #expect(!appModel.contains("LSRegisterURL"))
    #expect(!appModel.contains("client.requestInputMonitoringAccess()"))
    #expect(!appModel.contains("--request-input-monitoring"))
  }

  @Test
  func testApplicationServiceUsesMainAppLoginRegistration() throws {
    let root = try RepositoryRoot.from()
    let manager = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriverKit/ApplicationService/ApplicationServiceManager.swift"
      ),
      encoding: .utf8
    )
    let main = try String(
      contentsOf: root.appendingPathComponent("Sources/OpenJoystickDriver/main.swift"),
      encoding: .utf8
    )
    let bundles = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/bundles.sh"),
      encoding: .utf8
    )

    #expect(manager.contains("SMAppService { .mainApp }"))
    #expect(manager.contains("try mainAppService.register()"))
    #expect(!main.contains("OJD_APPLICATION_SERVICE"))
    #expect(!main.contains("ApplicationServiceManager.restart()"))
    #expect(!bundles.contains("Contents/Library/LaunchAgents"))
    #expect(!FileManager.default.fileExists(
      atPath: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/App/com.openjoystickdriver.service.plist"
      ).path
    ))
  }

}
