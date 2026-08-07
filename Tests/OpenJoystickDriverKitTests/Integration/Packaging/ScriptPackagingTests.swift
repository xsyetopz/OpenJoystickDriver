import Foundation
import Testing

struct ScriptPackagingTests {
  @Test func testJustfileExposesReleaseParityLocalInstallCommand() throws {
    let justfileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("justfile")
    let justfile = try String(contentsOf: justfileURL, encoding: .utf8)

    #expect(justfile.contains("release-local-install version=\"0.5.0-beta.1\""))
    #expect(justfile.contains("./scripts/ojd release install-local \"{{version}}\""))
    #expect(!justfile.contains("rm -rf"))
    #expect(!justfile.contains("cp -R"))
  }

  @Test func testLocalInstallUsesCanonicalVersionAndStagedReplacement() throws {
    let root = try RepositoryRoot.from()
    let install = try String(
      contentsOf: root.appendingPathComponent("scripts/release/install-local.sh"),
      encoding: .utf8
    )
    let package = try String(
      contentsOf: root.appendingPathComponent("scripts/release/package.sh"),
      encoding: .utf8
    )

    #expect(install.contains("VERSION=\"${1:-$OJD_DEFAULT_BUNDLE_SHORT_VERSION}\""))
    #expect(install.contains("APP_STAGED="))
    #expect(install.contains("APP_BACKUP="))
    #expect(install.contains("codesign --verify --deep --strict"))
    #expect(package.contains("release_ref=\"${GITHUB_REF_NAME:-}\""))
    #expect(package.contains("release_ref#v"))
    #expect(package.contains("OJD_DEFAULT_BUNDLE_SHORT_VERSION"))
    #expect(!package.contains("date -u"))
  }

  @Test func testBumpVersionSurfacesUseCurrentReleaseVersion() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let bundlesURL = rootURL.appendingPathComponent("scripts/build-tools/bundles.sh")
    let defaultsURL = rootURL.appendingPathComponent("scripts/platform/environment.sh")
    let justfileURL = rootURL.appendingPathComponent("justfile")
    let bumpURL = rootURL.appendingPathComponent("scripts/release/bump-version.sh")
    let bundles = try String(contentsOf: bundlesURL, encoding: .utf8)
    let defaults = try String(contentsOf: defaultsURL, encoding: .utf8)
    let justfile = try String(contentsOf: justfileURL, encoding: .utf8)
    let bumpScript = try String(contentsOf: bumpURL, encoding: .utf8)

    #expect(defaults.contains("OJD_DEFAULT_BUNDLE_SHORT_VERSION=\"0.5.0-beta.1\""))
    #expect(bundles.contains("OJD_DEFAULT_BUNDLE_SHORT_VERSION"))
    #expect(justfile.contains("release-local-install version=\"0.5.0-beta.1\""))
    #expect(bumpScript.contains("justfile"))
    #expect(!bundles.contains("0.5.0-alpha.3"))
    #expect(!justfile.contains("0.5.0-alpha.3"))
  }

  @Test func testDmgPackagingUsesNativeFinderStyling() throws {
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

  @Test func testBuildScriptPackagesOneSignedApplicationIdentity() throws {
    let root = try RepositoryRoot.from()
    let bundles = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/bundles.sh"),
      encoding: .utf8
    )
    let build = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/build.sh"),
      encoding: .utf8
    )
    #expect(build.contains("security find-identity -v -p codesigning"))
    #expect(bundles.contains("_require_codesign_identity"))
    #expect(bundles.contains(#""com.apple.developer.hid.virtual.device""#))
    #expect(bundles.contains("ojd_sign \"$GUI_APP\" --entitlements \"$GUI_ENTITLEMENTS\""))
    #expect(!bundles.contains("DAEMON_IDENTITY"))
    #expect(!bundles.contains("DAEMON_PROFILE"))
    #expect(!bundles.contains("OpenJoystickDriverDaemon"))
    #expect(!bundles.contains("Contents/Library/LoginItems"))
    #expect(!bundles.contains("Contents/Library/LaunchAgents"))
    #expect(!bundles.contains("com.openjoystickdriver.service.plist"))
  }

  @Test func testDriverKitBuildIsGeneratedAndVersionedFromReleaseEnvironment() throws {
    let root = try RepositoryRoot.from()
    let tooling = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/driverkit.sh"),
      encoding: .utf8
    )
    let bump = try String(
      contentsOf: root.appendingPathComponent("scripts/release/bump-version.sh"),
      encoding: .utf8
    )

    #expect(tooling.contains("DriverKitGenerator"))
    #expect(tooling.contains("OJD_BUNDLE_SHORT_VERSION"))
    #expect(tooling.contains("OJD_BUNDLE_VERSION"))
    #expect(tooling.contains("SwifterKitRuntime.xcodeproj"))
    #expect(!tooling.contains("plutil -replace CFBundleVersion"))
    #expect(!bump.contains("DriverKitExtension/Info.plist"))
  }

  @Test func testSwiftLintRunsStrictlyWithoutSuppressionBaseline() throws {
    let root = try RepositoryRoot.from()
    let buildScript = try String(
      contentsOf: root.appendingPathComponent("scripts/build-tools/build.sh"),
      encoding: .utf8
    )

    #expect(buildScript.contains("swiftlint lint --no-cache --strict"))
    #expect(!buildScript.contains("--baseline"))
    #expect(
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent(".swiftlint-baseline.json").path
      )
    )
  }

  @Test func testApplicationServiceUsesMainAppLoginRegistration() throws {
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
    #expect(
      !FileManager.default.fileExists(
        atPath: root.appendingPathComponent(
          "Sources/OpenJoystickDriver/App/com.openjoystickdriver.service.plist"
        ).path
      )
    )
  }

}
