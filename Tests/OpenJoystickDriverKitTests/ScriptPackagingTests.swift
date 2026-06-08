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
}
