import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.serialized)
struct SettingsRPCTests {
  private struct LoginFailure: Error, LocalizedError {
    var errorDescription: String? { "registration failed" }
  }

  @Test
  func getSettingsListsEveryKeyWithItsDefault() async throws {
    try await withServer { server, _ in
      let response = await handle(server, method: "getSettings", arguments: "{}")

      let payload = try decode(response)
      #expect(payload.settings.map(\.key) == ApplicationSettingKey.allCases)
      #expect(payload.value(of: .launchAtLogin) == false)
      #expect(payload.value(of: .notificationSounds) == true)
      #expect(payload.value(of: .includePrereleaseUpdates) == false)
      #expect(payload.value(of: .developerTools) == false)
    }
  }

  @Test
  func setSettingStoresADefaultsBackedValueAndReturnsEverySetting() async throws {
    try await withServer { server, defaults in
      let arguments = try encode(
        ApplicationServiceSettingArguments(key: .developerTools, value: true)
      )
      let response = await handle(server, method: "setSetting", arguments: arguments)

      #expect(try decode(response).value(of: .developerTools) == true)
      #expect(defaults.bool(forKey: "OpenJoystickDriver.developerTools.enabled"))
    }
  }

  @Test
  func setSettingAppliesLaunchAtLoginThroughTheLoginControl() async throws {
    try await withServer { server, _ in
      let arguments = try encode(
        ApplicationServiceSettingArguments(key: .launchAtLogin, value: true)
      )
      let response = await handle(server, method: "setSetting", arguments: arguments)

      #expect(try decode(response).value(of: .launchAtLogin) == true)
    }
  }

  @Test
  func setSettingReportsALoginItemThatMacOSKeptOff() async throws {
    try await withServer(loginAccepts: false) { server, _ in
      let arguments = try encode(
        ApplicationServiceSettingArguments(key: .launchAtLogin, value: true)
      )
      let response = await handle(server, method: "setSetting", arguments: arguments)

      #expect(try decode(response).value(of: .launchAtLogin) == false)
    }
  }

  @Test
  func setSettingFailsWhenTheLoginControlThrows() async throws {
    try await withServer(loginFails: true) { server, _ in
      let arguments = try encode(
        ApplicationServiceSettingArguments(key: .launchAtLogin, value: true)
      )
      let response = await handle(server, method: "setSetting", arguments: arguments)

      #expect(response.result == nil)
      #expect(response.error == "registration failed")
    }
  }

  @Test
  func setSettingRejectsAnUnknownKey() async throws {
    try await withServer { server, _ in
      let response = await handle(
        server,
        method: "setSetting",
        arguments: #"{"key":"no-such-setting","value":true}"#
      )

      #expect(response.result == nil)
      #expect(response.error != nil)
    }
  }

  private func encode(_ value: some Encodable) throws -> String {
    String(bytes: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
  }

  private func decode(_ response: LocalServiceRPCResponse) throws -> ApplicationSettingsPayload {
    try JSONDecoder().decode(
      ApplicationSettingsPayload.self,
      from: try #require(response.result, "\(response.error ?? "no error")")
    )
  }

  private func handle(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: String
  ) async -> LocalServiceRPCResponse {
    await server.handleLocalRPC(
      LocalServiceRPCRequest(method: method, arguments: Data(arguments.utf8))
    )
  }

  private func withServer(
    loginAccepts: Bool = true,
    loginFails: Bool = false,
    _ body: (ApplicationServiceServer, UserDefaults) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suiteName = "OpenJoystickDriverTests.SettingsRPC.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let login = Locked(false)
    let dispatcher = VirtualOutputRouter()
    let library = RemappingProfileLibrary(directory: directory)
    let postEventAccess = CoreGraphicsPostEventAccess()
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: router),
      permissionManager: PermissionManager(),
      dispatcher: dispatcher,
      remappingProfileLibrary: library,
      remappingRouter: router,
      postEventAccess: postEventAccess,
      userSpaceDispatcherFactory: ApplicationServiceRuntime.makeAutomaticUserSpaceDispatcher(
        context:
      ),
      defaults: defaults,
      personaDirectory: directory.appendingPathComponent("Personas", isDirectory: true),
      launchAtLogin: LaunchAtLoginControl(
        isEnabled: { login.withLock { $0 } },
        setEnabled: { enabled in
          if loginFails { throw LoginFailure() }
          if loginAccepts { login.withLock { $0 = enabled } }
        }
      )
    )
    try await body(server, defaults)
  }
}
