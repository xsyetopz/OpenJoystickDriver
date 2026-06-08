import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Daemon manager bundle paths")
struct DaemonManagerTests {
  @Test("bundled helper app URL points at the embedded helper app")
  func bundledHelperApplicationURL() {
    let url = DaemonManager.bundledHelperApplicationURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(
      url.path ==
        "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriverDaemon.app"
    )
  }
}
