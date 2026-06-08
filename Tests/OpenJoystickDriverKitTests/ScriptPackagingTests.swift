import Foundation
import Testing

struct ScriptPackagingTests {
  @Test
  func testDmgStylingAppleScriptOpensFinderDiskObject() throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("scripts/ojd-package.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(!script.contains("tell volumeRoot"))
    #expect(script.contains("set volumeName to \"OpenJoystickDriver\""))
    #expect(script.contains("set volumeDisk to disk volumeName"))
    #expect(script.contains("open volumeDisk"))
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
    #expect(
      packaging.contains(
        "/Applications/OpenJoystickDriver.app/Contents/Library/LoginItems/" +
        "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
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
    #expect(daemonMain.contains("NSApplication.shared.setActivationPolicy(.accessory)"))
    #expect(daemonMain.contains("NSApp.activate(ignoringOtherApps: true)"))
    #expect(daemonMain.contains("OJD_PERMISSION_PROMPT_ONLY"))
  }

}
