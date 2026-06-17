import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Daemon manager bundle paths")
struct DaemonManagerTests {
  @Test("bundled daemon app URL points at the embedded daemon app")
  func bundledDaemonApplicationURL() {
    let url = DaemonManager.bundledDaemonApplicationURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(
      url.path ==
        "/Applications/OpenJoystickDriver.app/Contents/Library/LoginItems/" +
        "OpenJoystickDriverDaemon.app"
    )
  }

  @Test("bundled daemon executable URL points inside the daemon app")
  func bundledDaemonExecutableURL() {
    let url = DaemonManager.bundledDaemonExecutableURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(
      url.path ==
        "/Applications/OpenJoystickDriver.app/Contents/Library/LoginItems/" +
        "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
    )
  }


  @Test("unbundled daemon executable URL points to sibling build product")
  func unbundledDaemonExecutableURL() {
    let url = DaemonManager.daemonExecutableURL(
      forMainBundleURL: URL(fileURLWithPath: "/repo/.build/debug", isDirectory: true)
    )

    #expect(url.path == "/repo/.build/debug/OpenJoystickDriverDaemon")
  }

  @Test("app-bundled daemon executable URL points inside embedded daemon app")
  func appBundledDaemonExecutableURL() {
    let url = DaemonManager.daemonExecutableURL(
      forMainBundleURL: URL(
        fileURLWithPath: "/Applications/OpenJoystickDriver.app",
        isDirectory: true
      )
    )

    #expect(
      url.path ==
        "/Applications/OpenJoystickDriver.app/Contents/Library/LoginItems/" +
        "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
    )
  }

  @Test("daemon lifecycle uses SMAppService on modern macOS")
  func daemonLifecycleUsesSMAppService() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let sourceURL = rootURL.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Daemon/DaemonManager.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let compactSource = source.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression
    )

    #expect(source.contains("private static var usesLaunchctlAgentRegistration: Bool"))
    #expect(source.contains("if #available(macOS 13.0, *) {"))
    #expect(source.contains("return false"))
    #expect(source.contains("try appService.register()"))
    #expect(source.contains("try appService.unregister()"))
    #expect(source.contains("print(\"[DaemonManager] Installed (SMAppService)\")"))
    #expect(source.contains("print(\"[DaemonManager] Restarted (SMAppService)\")"))
    #expect(
      compactSource.contains("if usesLaunchctlAgentRegistration { try legacyInstall() return }")
    )
    #expect(
      compactSource.contains("if usesLaunchctlAgentRegistration { try legacyUninstall() return }")
    )
    #expect(
      compactSource.contains("if usesLaunchctlAgentRegistration { try legacyRestart() return }")
    )
  }

  @Test("launchctl print parser recognizes a running daemon")
  func launchctlPrintParserRecognizesRunningDaemon() {
    let output = """
      gui/501/com.openjoystickdriver.daemon = {
        active count = 2
        type = Submitted
        state = running
        pid = 16484
        job state = running
      }
      """

    #expect(DaemonManager.launchctlPrintShowsRunning(output))
  }

  @Test("launchctl print parser rejects non-running daemon states")
  func launchctlPrintParserRejectsNonRunningDaemonStates() {
    let output = """
      gui/501/com.openjoystickdriver.daemon = {
        active count = 0
        state = spawn scheduled
        job state = spawn failed
      }
      """

    #expect(!DaemonManager.launchctlPrintShowsRunning(output))
  }

}
