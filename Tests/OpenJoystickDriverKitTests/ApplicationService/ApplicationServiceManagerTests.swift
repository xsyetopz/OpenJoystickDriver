import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Application service lifecycle") struct ApplicationServiceManagerTests {
  @Test("main app executable owns runtime") func applicationExecutableURL() {
    let url = ApplicationServiceManager.applicationExecutableURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(url.path == "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver")
    #expect(!url.path.contains("LoginItems"))
    #expect(!url.path.contains("OpenJoystickDriverDaemon"))
  }

  @Test("main app has a stable service identity") func serviceIdentity() {
    #expect(ApplicationServiceManager.label == "com.openjoystickdriver")
  }
}
