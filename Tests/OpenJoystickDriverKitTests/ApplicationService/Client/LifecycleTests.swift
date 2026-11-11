import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite("Application service lifecycle")
struct LifecycleTests {
  @Test("login registration is skipped while the settings file is rejected")
  func loginRegistrationDoesNotProceedOnAnUnreadableSettingsFile() throws {
    let root = RootedDataDirectory.temporary()
    let store = SettingsStore(directory: root)
    try FileManager.default.createDirectory(
      at: store.folderURL,
      withIntermediateDirectories: true
    )
    try PropertyListFixture.bytes(
      json: #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings", "#
        + #""showInMenuBar": false}"#
    ).write(to: store.userFileURL)

    #expect(throws: SettingsStoreError.storedNoVisibleEntryPoint(file: store.userFileURL.path)) {
      try ApplicationServiceManager.installByDefaultIfNeeded(settings: store)
    }
  }

  @Test("main app executable owns runtime")
  func applicationExecutableURL() {
    let url = ApplicationServiceManager.applicationExecutableURL(
      in: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app", isDirectory: true)
    )

    #expect(url.path == "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver")
    #expect(!url.path.contains("LoginItems"))
    #expect(!url.path.contains("OpenJoystickDriverDaemon"))
  }

  @Test("main app has a stable service identity")
  func serviceAddress() { #expect(ApplicationServiceManager.label == "com.openjoystickdriver") }

  @Test("login registration uses the main-app registration client")
  func registrationUsesClient() throws {
    let service = RecordingRegistration(status: .notRegistered)

    try ApplicationServiceManager.registerMainApp(using: service)

    #expect(service.registerCount == 1)
    #expect(service.unregisterCount == 0)
  }

  @Test("login registration messages are written to the information stream")
  func registrationMessagesAreInformation() throws {
    let pipe = Pipe()

    try ApplicationServiceManager.registerMainApp(
      using: RecordingRegistration(status: .notRegistered),
      information: pipe.fileHandleForWriting
    )
    try ApplicationServiceManager.unregisterMainApp(
      using: RecordingRegistration(status: .enabled),
      information: pipe.fileHandleForWriting
    )
    try pipe.fileHandleForWriting.close()
    let text = try #require(
      String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    )

    #expect(
      text
        == "[ApplicationServiceManager] Main app registered for login\n"
        + "[ApplicationServiceManager] Main app removed from login items\n"
    )
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
