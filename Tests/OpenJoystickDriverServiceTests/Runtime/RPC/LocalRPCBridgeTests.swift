import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

@Suite(.serialized, .timeLimit(.minutes(2)), .removingTemporarySockets)
struct LocalRPCBridgeTests {
  private static let controllerMethodNames: Set = [
    "getStatus", "requestRequiredAccess", "requestAccess", "requestBluetoothAccess",
    "getControllerState", "getPacketLog",
    "getVirtualOutputState",
    "sendControllerOutput", "playControllerSpeaker", "stopControllerSpeaker",
    "previewPhysicalColor", "releasePhysicalColorPreview",
    "getVirtualDeviceDiagnostics", "getFrameTimings", "waitForServiceStatusChange",
    "sendTestNotification", "reportTestNotificationResult", "setVirtualHIDProfileOverride",
    "resetVirtualHIDProfileOverride", "setControllerServer", "setControllerTuning",
    "openVirtualFeed", "exchangeVirtualFeed",
    "closeVirtualFeed", "suspendController", "resumeController",
    "disconnectWirelessController", "resetSettings", "getSettings", "setSetting",
    "getAccessStatus", "setAccessEnabled", "grantAccess", "revokeAccess",
    "grantTokenAccess", "setWebAccess",
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
  func theServersFeedsKeepTheProductionIdleTimeout() async throws {
    try await withServer { server in
      #expect(server.virtualFeeds.idleTimeout == 2)
    }
  }

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
  func requestBluetoothAccessAsksTheControlAndGetStatusReportsItsState() async throws {
    let requests = RequestCounter()
    let control = BluetoothAccessControl(
      state: { requests.hasRequest ? .granted : .notAsked },
      request: {
        requests.increment()
        return .granted
      }
    )
    try await withServer(bluetoothAccess: control) { server in
      let before = try JSONDecoder().decode(
        ApplicationServiceStatusPayload.self,
        from: await server.getStatus()
      )
      #expect(before.bluetoothAccess == .notAsked)
      #expect(!requests.hasRequest)
      #expect(server.requestBluetoothAccess() == .granted)
      #expect(requests.count == 1)
    }
  }

  @Test
  func aServerWithoutBluetoothReportsItUnavailable() async throws {
    try await withServer { server in
      #expect(server.requestBluetoothAccess() == .unavailable)
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
      let socketPath = unregisteredSocketPath()
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { await server.handleLocalRPC($0) }
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

  @Test
  func aStatusNotificationReachesAWaitingClient() async throws {
    let statusCenter = NotificationCenter()
    try await withServer(statusCenter: statusCenter) { server in
      let socketPath = unregisteredSocketPath()
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { await server.handleLocalRPC($0) }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let client = ApplicationServiceClient(socketPath: socketPath)
      await client.connect()
      let baseline = try await client.waitForServiceStatusChange(after: nil).revision

      async let next = client.waitForServiceStatusChange(after: baseline)
      try await Task.sleep(nanoseconds: 100_000_000)
      statusCenter.post(name: .ojdServiceStatusDidChange, object: nil)

      #expect(try await next.revision != baseline)
    }
  }

  @Test
  func sendTestNotificationEndsWithTheAppsReport() async throws {
    try await withServer { server in
      let socketPath = unregisteredSocketPath()
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { await server.handleLocalRPC($0) }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let app = ApplicationServiceClient(socketPath: socketPath)
      await app.connect()
      let cli = ApplicationServiceClient(socketPath: socketPath)
      await cli.connect()
      let baseline = try await app.waitForServiceStatusChange(after: nil).revision

      async let outcome = cli.sendTestNotification()
      let reply = try await app.waitForServiceStatusChange(after: baseline)
      let id = try #require(reply.announcement)
      #expect(reply.event == .testNotification)
      #expect(
        try await app.reportTestNotificationResult(announcement: id, outcome: .denied)
      )

      #expect(try await outcome == .denied)
      #expect(
        try await !app.reportTestNotificationResult(announcement: id, outcome: .shown)
      )
    }
  }

  @Test
  func aClientThatClosesDuringAHeldWaitLeavesTheHeldCountAndMissesTheAnnouncement() async throws {
    try await withServer { server in
      let socketPath = unregisteredSocketPath()
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { await server.handleLocalRPC($0) }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let app = ApplicationServiceClient(socketPath: socketPath)
      await app.connect()
      let baseline = try await app.waitForServiceStatusChange(after: nil).revision
      let (registered, registeredGate) = AsyncStream.makeStream(of: Void.self)
      let (released, releasedGate) = AsyncStream.makeStream(of: Void.self)
      defer {
        registeredGate.finish()
        releasedGate.finish()
      }
      server.statusChanges.heldWaitDidRegister = { registeredGate.yield() }
      server.statusChanges.heldWaitDidRelease = { releasedGate.yield() }

      let descriptor = try LocalServiceRPCTransport.openConnectedSocket(
        timeoutSeconds: 5,
        socketPath: socketPath
      )
      let request = LocalServiceRPCRequest(
        method: ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue,
        arguments: try JSONEncoder().encode(LocalServiceRPCStatusChangeArguments(after: baseline))
      )
      try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(request), to: descriptor)
      for await _ in registered { break }

      Darwin.close(descriptor)
      for await _ in released { break }
      #expect(server.statusChanges.heldWaitCount == 0)

      async let outcome = app.sendTestNotification()
      let reply = try await app.waitForServiceStatusChange(after: baseline)
      let id = try #require(reply.announcement)
      #expect(
        try await app.reportTestNotificationResult(announcement: id, outcome: .shown)
      )
      #expect(try await outcome == .shown)
    }
  }

  @Test
  func aClientThatClosesASendTestNotificationRequestWithdrawsIt() async throws {
    try await withServer { server in
      let socketPath = unregisteredSocketPath()
      let rpcServer = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { await server.handleLocalRPC($0) }
      )
      try rpcServer.start()
      defer { rpcServer.stop() }
      let app = ApplicationServiceClient(socketPath: socketPath)
      await app.connect()
      let baseline = try await app.waitForServiceStatusChange(after: nil).revision
      let (withdrawn, withdrawnGate) = AsyncStream.makeStream(of: Void.self)
      defer { withdrawnGate.finish() }
      server.statusChanges.testNotificationRequestDidWithdraw = { withdrawnGate.yield() }

      let descriptor = try LocalServiceRPCTransport.openConnectedSocket(
        timeoutSeconds: 5,
        socketPath: socketPath
      )
      let request = LocalServiceRPCRequest(
        method: ApplicationServiceRPCMethod.sendTestNotification.rawValue,
        arguments: try JSONEncoder().encode(LocalServiceRPCEmptyArguments())
      )
      try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(request), to: descriptor)
      let reply = try await app.waitForServiceStatusChange(after: baseline)
      let id = try #require(reply.announcement)

      Darwin.close(descriptor)
      for await _ in withdrawn { break }

      #expect(
        try await !app.reportTestNotificationResult(announcement: id, outcome: .shown)
      )
    }
  }

  @Test
  func frameTimingsDecodeTheLastSecondsAndTheEmptyRequest() async throws {
    try await withServer { server in
      for lastSeconds in [nil, 1, FrameTimingRecorder.windowSeconds] {
        let arguments = try JSONEncoder().encode(
          LocalServiceRPCFrameTimingsArguments(lastSeconds: lastSeconds)
        )
        let response = await handle(
          server,
          method: ApplicationServiceRPCMethod.getFrameTimings.rawValue,
          arguments: arguments
        )

        #expect(response.error == nil, "\(String(describing: lastSeconds))")
        let encoded = try JSONDecoder().decode(Data.self, from: try #require(response.result))
        let payload = try JSONDecoder().decode(
          ApplicationServiceFrameTimingsPayload.self,
          from: encoded
        )
        #expect(payload.controllers.isEmpty)
      }
    }
  }

  @Test
  func frameTimingsRefuseALastSecondsOutsideTheWindowAsInvalidRequest() async throws {
    try await withServer { server in
      for lastSeconds in [-1, 0, FrameTimingRecorder.windowSeconds + 1] {
        let arguments = try JSONEncoder().encode(
          LocalServiceRPCFrameTimingsArguments(lastSeconds: lastSeconds)
        )
        let response = await handle(
          server,
          method: ApplicationServiceRPCMethod.getFrameTimings.rawValue,
          arguments: arguments
        )

        #expect(response.result == nil, "\(lastSeconds)")
        #expect(response.error == FrameTimingsRequestError.invalidRequest.errorDescription)
        #expect(response.error == Localization().string("cli.diagnose.group.framesInvalidRequest"))
      }
    }
  }

  @Test
  func aReportOfNoAnswerIsRefusedWithItsOwnText() async throws {
    try await withServer { server in
      let arguments = try JSONEncoder().encode(
        TestNotificationReport(announcement: UUID(), outcome: .noAnswer)
      )
      let response = await handle(
        server,
        method: ApplicationServiceRPCMethod.reportTestNotificationResult.rawValue,
        arguments: arguments
      )

      #expect(response.result == nil)
      #expect(response.error == TestNotificationReportError.noAnswerReported.errorDescription)
      #expect(
        response.error == Localization().string("ui.settings.notifications.testReportNoAnswer")
      )
      #expect(response.error != ApplicationServiceClientError.invalidResponse.errorDescription)
    }
  }

  @Test
  func aVirtualOutputStatusChangeAnnouncesOnceAfterTheLockIsReleased() async throws {
    try await withServer { server in
      let lockHeldDuringPost = LockedFlag()
      let observer = NotificationCenter.default.addObserver(
        forName: .ojdServiceStatusDidChange,
        object: server,
        queue: nil
      ) { _ in
        // A held lock cannot be taken again; `try` fails the check while the lock is held.
        if server.userSpaceLock.try() {
          server.userSpaceLock.unlock()
        } else {
          lockHeldDuringPost.set()
        }
      }
      defer { NotificationCenter.default.removeObserver(observer) }

      let count = await Self.announcements(from: server) {
        server.withUserSpaceState { server.userSpaceStatus = .error("failed") }
      }

      #expect(count == 1)
      #expect(!lockHeldDuringPost.isSet)
    }
  }

  @Test
  func aRepeatedVirtualOutputStatusAnnouncesNothing() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server) {
          server.withUserSpaceState { server.userSpaceStatus = .off }
        } == 0
      )
    }
  }

  @Test
  func aProfileReloadAnnouncesFromTheRemappingCoordinator() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server.remappingRequests) {
          await server.reloadRemappingProfiles()
        } == 1
      )
    }
  }

  @Test
  func anOverrideResetAnnouncesFromTheServer() async throws {
    try await withServer { server in
      #expect(
        await Self.announcements(from: server) { _ = server.resetVirtualHIDProfileSettings() } == 1
      )
    }
  }

  /// How many service status changes `source` announces during `action`.
  private static func announcements(
    from source: AnyObject,
    _ action: () async -> Void
  ) async -> Int {
    let count = AnnouncementCount()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: source,
      queue: nil
    ) { _ in count.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }
    await action()
    return count.value
  }

  private static func unknownMethodMessage(_ name: String) -> String {
    "Unknown RPC method: \(name)"
  }

  @Test
  func aListenerRestartAfterStopBeginsRefusesAsStopping() async throws {
    let socketPath = temporarySocketPath()
    try await withServer { server in
      let listener = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { _ in
          return LocalServiceRPCResponse(result: nil, error: nil)
        }
      )
      server.rpcServerLock.withLock { server.rpcServer = listener }
      try listener.start()
      defer { listener.stop() }

      // While the service runs, a listener that already runs is reported as such.
      #expect(throws: LocalServiceRPCError.alreadyRunning) {
        try server.restartListener(of: listener)
      }
      await server.stop()
      #expect(throws: LocalServiceRPCError.stopping) {
        try server.restartListener(of: listener)
      }
    }
  }

  private func handle(
    _ server: ApplicationServiceServer,
    method: String,
    arguments: Data
  ) async -> LocalServiceRPCResponse {
    let request = LocalServiceRPCRequest(method: method, arguments: arguments)
    return await server.handleLocalRPC(request)
  }

  /// Runs `body` with a server whose status revision moves only on posts to `statusCenter`, so the
  /// announcements of other tests in the process cannot answer a wait of this one.
  private func withServer(
    statusCenter: NotificationCenter = NotificationCenter(),
    bluetoothAccess: BluetoothAccessControl? = nil,
    _ body: (ApplicationServiceServer) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let dispatcher = VirtualOutputRouter()
    let library = RemappingProfileLibrary(directory: directory)
    let postEventAccess = CoreGraphicsPostEventAccess()
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: CoreGraphicsSystemInputSink(access: postEventAccess)),
      virtualOutput: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: router, installationKey: testPortKeyInstallationKey),
      permissionManager: .grantingAll(),
      dispatcher: dispatcher,
      remappingProfileLibrary: library,
      remappingRouter: router,
      postEventAccess: postEventAccess,
      installationKey: testPortKeyInstallationKey,
      userSpaceDispatcherFactory: ApplicationServiceRuntime.makeAutomaticUserSpaceDispatcher(
        context:
      ),
      settings: settings,
      personaDirectory: directory.appendingPathComponent("Personas", isDirectory: true),
      statusChanges: ServiceStatusChanges(
        center: statusCenter,
        workspaceCenter: NotificationCenter()
      ),
      bluetoothAccess: bluetoothAccess
    )
    try await body(server)
  }
}

private final class AnnouncementCount: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var flag = false
  var isSet: Bool { lock.withLock { flag } }
  func set() { lock.withLock { flag = true } }
}

/// Records the Bluetooth access requests that a test server received.
private final class RequestCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [Void] = []
  var count: Int { lock.withLock { requests.count } }
  var hasRequest: Bool { lock.withLock { !requests.isEmpty } }
  func increment() { lock.withLock { requests.append(()) } }
}
