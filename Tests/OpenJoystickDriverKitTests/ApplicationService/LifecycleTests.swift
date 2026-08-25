import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Application service lifecycle") struct LifecycleTests {
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

  @Test("login registration uses the main-app registration client") func registrationUsesClient()
    throws
  {
    let service = RecordingRegistration(status: .notRegistered)

    try ApplicationServiceManager.registerMainApp(using: service)

    #expect(service.registerCount == 1)
    #expect(service.unregisterCount == 0)
  }
}

private final class RecordingRegistration: ApplicationServiceRegistration, @unchecked Sendable {
  let status: ApplicationServiceRegistrationStatus
  var registerCount = 0
  var unregisterCount = 0

  init(status: ApplicationServiceRegistrationStatus) { self.status = status }

  func register() { registerCount += 1 }

  func unregister() { unregisterCount += 1 }
}
