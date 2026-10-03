import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.serialized)
struct LocalRPCBridgeTests {
  private static let controllerMethodNames: Set = [
    "getStatus", "requestRequiredAccess", "requestAccess", "getControllerState", "getPacketLog",
    "getVirtualOutputState",
    "sendControllerOutput", "previewPhysicalColor", "releasePhysicalColorPreview",
    "setSuppressOutput", "getVirtualDeviceDiagnostics", "setVirtualHIDProfileOverride",
    "resetVirtualHIDProfileOverride", "suspendController", "resumeController",
    "disconnectWirelessController", "resetSettings", "getSettings", "setSetting",
  ]
  private static let remappingMethodNames: Set = [
    "remappingMotionCalibration", "pairRemappingJoyCons", "unpairRemappingJoyCons",
    "getRemappingSnapshot", "getRemappingProfile", "createRemappingProfile",
    "updateRemappingProfile", "deleteRemappingProfile", "importRemappingProfile",
    "activateRemappingProfile", "deactivateRemappingProfile", "deactivateRemappingProfileByID",
    "getRemappingPostEventAccess", "requestRemappingPostEventAccess",
    "deleteDamagedRemappingProfile", "resetRemappingProfileLibrary",
  ]

  @Test
  func methodRawValuesAreTheWireNames() {
    #expect(
      Set(ApplicationServiceRPCMethod.allCases.map(\.rawValue))
        == Self.controllerMethodNames.union(Self.remappingMethodNames)
    )
  }

  @Test(arguments: ApplicationServiceRPCMethod.allCases)
  func everyMethodNameDispatchesToItsHandler(_ method: ApplicationServiceRPCMethod) async throws {
    try await withServer { server in
      let response = await handle(server, method: method.rawValue, arguments: Data("{".utf8))

      #expect(response.result == nil)
      #expect(response.error != Self.unknownMethodMessage(method.rawValue))
      if Self.remappingMethodNames.contains(method.rawValue) {
        #expect(response.remappingError?.code == .invalidArguments)
      } else {
        #expect(response.error != nil)
        #expect(response.remappingError == nil)
      }
    }
  }

  @Test
  func unknownMethodNameFailsWithTheUnknownMethodMessage() async throws {
    try await withServer { server in
      let response = await handle(server, method: "noSuchMethod", arguments: Data("{}".utf8))

      #expect(response.error == Self.unknownMethodMessage("noSuchMethod"))
      #expect(response.remappingError == nil)
    }
  }

  @Test
  func remappingFailureTravelsInTheStructuredErrorField() async throws {
    try await withServer { server in
      let arguments = try JSONEncoder().encode(
        ApplicationServiceRemappingProfileIDArguments(profileID: UUID())
      )
      let response = await handle(server, method: "getRemappingProfile", arguments: arguments)

      let error = try #require(response.remappingError)
      #expect(error.code == .profileNotFound)
      #expect(response.error == error.message)
    }
  }

  @Test
  func remappingFailureArrivesAtTheClientAsTheTypedError() async throws {
    try await withServer { server in
      let socketPath = "/tmp/com.openjoystickdriver.bridge.\(UUID().uuidString).rpc"
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { request, completion in Task { completion(await server.handleLocalRPC(request)) }
        }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let client = ApplicationServiceClient(socketPath: socketPath)
      await client.connect()

      let error = await #expect(throws: ApplicationServiceRemappingRPCError.self) {
        try await client.getRemappingProfile(id: UUID())
      }
      #expect(error?.code == .profileNotFound)
    }
  }

  private static func unknownMethodMessage(_ name: String) -> String {
    "Unknown RPC method: \(name)"
  }

  private func handle(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: Data
  ) async -> LocalServiceRPCResponse {
    let request = LocalServiceRPCRequest(method: method, arguments: arguments)
    return await server.handleLocalRPC(request)
  }

  private func withServer(_ body: (ApplicationServiceServer) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suiteName = "OpenJoystickDriverTests.LocalRPCBridge.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
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
      defaults: defaults
    )
    try await body(server)
  }
}
