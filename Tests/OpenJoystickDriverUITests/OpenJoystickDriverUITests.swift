// UI tests need XCUIApplication, which only XCTest has.
import AppKit
import XCTest

final class OpenJoystickDriverUITests: XCTestCase {
  @MainActor
  func testLaunchesAndKeepsRunning() throws {
    // A second copy exits at startup because the running one owns the app's RPC service.
    let bundleIdentifier = "com.openjoystickdriver"
    if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
      throw XCTSkip("Quit the running OpenJoystickDriver to run this test.")
    }
    let app = XCUIApplication()
    app.launchEnvironment["OJD_HIDDEN"] = "1"
    app.launch()
    XCTAssertNotEqual(app.state, .notRunning)
    app.terminate()
  }
}
