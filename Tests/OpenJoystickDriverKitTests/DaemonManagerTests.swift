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
        "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriverDaemon.app"
    )
  }

  @Test("bundled daemon executable URL points inside the daemon app")
  func bundledDaemonExecutableURL() {
    let url = DaemonManager.bundledDaemonExecutableURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(
      url.path ==
        "/Applications/OpenJoystickDriver.app/Contents/MacOS/" +
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
        "/Applications/OpenJoystickDriver.app/Contents/MacOS/" +
        "OpenJoystickDriverDaemon.app/Contents/MacOS/OpenJoystickDriverDaemon"
    )
  }

}
