// UI tests need XCUIApplication, which only XCTest has.
import XCTest

final class OpenJoystickDriverUITests: XCTestCase {
  @MainActor
  func testLaunchesAndKeepsRunning() {
    let app = XCUIApplication()
    app.launchEnvironment["OJD_HIDDEN"] = "1"
    app.launch()
    XCTAssertNotEqual(app.state, .notRunning)
    app.terminate()
  }
}
