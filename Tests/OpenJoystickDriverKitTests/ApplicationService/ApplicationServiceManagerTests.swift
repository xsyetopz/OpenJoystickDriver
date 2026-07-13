import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Application service lifecycle")
struct ApplicationServiceManagerTests {
  @Test("main app executable owns runtime")
  func applicationExecutableURL() {
    let url = ApplicationServiceManager.applicationExecutableURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(url.path == "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver")
    #expect(!url.path.contains("LoginItems"))
    #expect(!url.path.contains("OpenJoystickDriverDaemon"))
  }

  @Test("main app and obsolete registrations have distinct identities")
  func serviceIdentity() {
    #expect(ApplicationServiceManager.label == "com.openjoystickdriver")
    #expect(ApplicationServiceManager.obsoleteAgentLabel == "com.openjoystickdriver.service")
    #expect(ApplicationServiceManager.legacyDaemonLabel == "com.openjoystickdriver.daemon")
  }

  @Test(
    "migration waits for both obsolete jobs and the daemon process",
    arguments: [
      (false, false, false, true),
      (true, false, false, false),
      (false, true, false, false),
      (false, false, true, false),
    ]
  )
  func obsoleteRuntimeExitPolicy(
    agentIsLoaded: Bool,
    daemonIsLoaded: Bool,
    daemonProcessIsRunning: Bool,
    expected: Bool
  ) {
    #expect(
      ApplicationServiceManager.obsoleteRuntimesHaveStopped(
        agentIsLoaded: agentIsLoaded,
        daemonIsLoaded: daemonIsLoaded,
        daemonProcessIsRunning: daemonProcessIsRunning
      ) == expected
    )
  }
}
