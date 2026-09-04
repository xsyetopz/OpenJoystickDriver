import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RemappingRequestCoordinatorTests {
  @Test func fullCRUDImportActivationAndDeactivationUseOneServiceOwnedLibrary() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop")

    var snapshot = try await harness.coordinator.create(original).get()
    #expect(snapshot.profiles == [original])
    #expect(try await harness.coordinator.profile(id: original.id).get() == original)

    let updated = profile(id: original.id, name: "Desktop Updated", key: .a)
    snapshot = try await harness.coordinator.update(updated, expectedCurrent: original).get()
    #expect(snapshot.profiles == [updated])

    let imported = profile(id: original.id, name: "Desktop Imported", key: .b)
    snapshot = try await harness.coordinator.importProfile(imported).get()
    #expect(snapshot.profiles == [imported])

    snapshot = try await harness.coordinator.activate(id: original.id).get()
    #expect(snapshot.activeProfiles.map(\.profileID) == [original.id])

    snapshot = try await harness.coordinator.deactivate(vendorID: 1118, productID: 654).get()
    #expect(snapshot.activeProfiles.isEmpty)

    snapshot = try await harness.coordinator.delete(id: original.id).get()
    #expect(snapshot.profiles.isEmpty)
    let missing = await harness.coordinator.profile(id: original.id)
    #expect(
      missing
        == .failure(
          ApplicationServiceRemappingRPCError(
            code: .profileNotFound,
            message: "The remapping profile \(original.id.uuidString) does not exist."
          )
        )
    )
  }

  @Test func activeUpdateAndDeleteReleaseHeldStateBeforeSuccess() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop", key: .space)
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(
      events: [.buttonPressed(.a)],
      from: device
    )

    let updated = profile(id: original.id, name: "Desktop", key: .b)
    _ = try await harness.coordinator.update(updated, expectedCurrent: original).get()
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space))
      ]
    )

    try await harness.routerHarness.router.dispatchCausally(
      events: [.buttonPressed(.a)],
      from: device
    )
    _ = try await harness.coordinator.delete(id: updated.id).get()
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.b)),
        .system(.keyUp(.b))
      ]
    )
    #expect(await harness.routerHarness.router.status(for: device)?.selection == .compatibility)
  }

  @Test func staleSecondClientReceivesTypedConflictWithoutMutationOrOutputDrain() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop", key: .space)
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(
      events: [.buttonPressed(.a)],
      from: device
    )
    harness.routerHarness.recorder.removeAll()

    let firstUpdate = profile(id: original.id, name: "Desktop", key: .a)
    _ = try await harness.coordinator.update(firstUpdate, expectedCurrent: original).get()
    harness.routerHarness.recorder.removeAll()
    let bytesAfterFirstUpdate = try Data(contentsOf: harness.routerHarness.fileURL)
    let routeAfterFirstUpdate = await harness.routerHarness.router.status(for: device)
    let staleUpdate = profile(id: original.id, name: "Desktop", key: .b)

    let result = await harness.coordinator.update(staleUpdate, expectedCurrent: original)

    #expect(
      result
        == .failure(
          ApplicationServiceRemappingRPCError(
            code: .profileUpdateConflict,
            message: "The remapping profile \(original.id.uuidString) changed since it was read."
          )
        )
    )
    #expect(try Data(contentsOf: harness.routerHarness.fileURL) == bytesAfterFirstUpdate)
    #expect(try await harness.routerHarness.library.profile(id: original.id) == firstUpdate)
    #expect(await harness.routerHarness.router.status(for: device) == routeAfterFirstUpdate)
    #expect(harness.routerHarness.recorder.snapshot().isEmpty)
  }

  @Test func movingAnActiveProfileRefreshesItsFormerModelAndClearsSelection() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(
      events: [.buttonPressed(.a)],
      from: device
    )

    let moved = profile(id: original.id, name: "Desktop", vendorID: 1356, productID: 2508)
    let snapshot = try await harness.coordinator.update(moved, expectedCurrent: original).get()

    #expect(snapshot.activeProfiles.isEmpty)
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space))
      ]
    )
    #expect(await harness.routerHarness.router.status(for: device)?.selection == .compatibility)
  }

  @Test func snapshotPreservesExactSameModelRoutesWithoutSerialNumbers() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let mapped = profile(name: "Desktop")
    _ = try await harness.coordinator.create(mapped).get()
    _ = try await harness.coordinator.activate(id: mapped.id).get()
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)
    try await harness.routerHarness.router.dispatchCausally(events: [], from: first)
    try await harness.routerHarness.router.dispatchCausally(events: [], from: second)

    let snapshot = try await harness.coordinator.snapshot().get()
    #expect(snapshot.routes.count == 2)
    #expect(
      Set(snapshot.routes.map(\.runtimeIdentifier)) == [
        first.runtimeIdentifier, second.runtimeIdentifier
      ]
    )
    #expect(snapshot.routes.allSatisfy { $0.selection == .remapping })
    #expect(snapshot.routes.allSatisfy { $0.activeProfileID == mapped.id })
    let encoded = try #require(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
    #expect(!encoded.contains("serial"))
  }

  @Test func permissionRequestReturnsAuthoritativePreflightReadbackWithoutTrustingRequestResult()
    async throws
  {
    let probe = RPCPostEventProbe(preflight: [false, false, true], requestResult: false)
    let harness = try await makeHarness(postEventProbe: probe)
    defer { harness.routerHarness.removeFiles() }

    #expect(try await harness.coordinator.currentPostEventAccess().get() == .notAuthorized)
    #expect(try await harness.coordinator.requestPostEventAccess().get() == .granted)
    #expect(probe.requestCount == 1)
    #expect(probe.preflightCount == 3)
  }

  @Test func corruptStoreAndRouterFailuresCrossAsStableTypedErrors() async throws {
    let corruptHarness = try await makeHarness()
    defer { corruptHarness.routerHarness.removeFiles() }
    try Data("not json".utf8).write(to: corruptHarness.routerHarness.fileURL)
    let corrupt = await corruptHarness.coordinator.snapshot()
    #expect(
      corrupt
        == .failure(
          ApplicationServiceRemappingRPCError(
            code: .corruptLibrary,
            message: "The remapping profile library is corrupt."
          )
        )
    )

    let stoppedHarness = try await makeHarness()
    defer { stoppedHarness.routerHarness.removeFiles() }
    let mapped = profile(name: "Desktop")
    _ = try await stoppedHarness.coordinator.create(mapped).get()
    try await stoppedHarness.routerHarness.router.shutdown()
    let activation = await stoppedHarness.coordinator.activate(id: mapped.id)
    guard case .failure(let activationError) = activation else {
      Issue.record("Expected activation failure after router shutdown.")
      return
    }
    #expect(activationError.code == .routerShutDown)
    #expect(activationError.message == "The remapping output router has shut down.")
    #expect(
      try await stoppedHarness.routerHarness.library.activeProfile(vendorID: 1118, productID: 654)
        == nil
    )
  }

  @Test func failedActiveModelMoveRestoresExactLibraryAndBothRoutes() async throws {
    let harness = try makeRollbackHarness()
    defer { harness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let oldDevice = remappingRouterDevice(1)
    let newDevice = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [], from: newDevice)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: oldDevice)
    let exactPriorBytes = try Data(contentsOf: harness.fileURL)
    let priorFilePermissions = try permissions(at: harness.fileURL)
    let priorParentPermissions = try permissions(at: harness.fileURL.deletingLastPathComponent())
    harness.sink.failNextAction()

    let moved = profile(id: original.id, name: original.name, vendorID: 1356, productID: 2508)
    let result = await harness.coordinator.update(moved, expectedCurrent: original)

    expectRecoveredEngineFailure(result)
    #expect(try Data(contentsOf: harness.fileURL) == exactPriorBytes)
    #expect(try permissions(at: harness.fileURL) == priorFilePermissions)
    #expect(
      try permissions(at: harness.fileURL.deletingLastPathComponent()) == priorParentPermissions
    )
    #expect(try await harness.library.profile(id: original.id) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1118, productID: 654) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1356, productID: 2508) == nil)
    #expect(await harness.router.status(for: oldDevice)?.activeProfileID == original.id)
    #expect(await harness.router.status(for: newDevice)?.selection == .compatibility)
  }

  @Test(arguments: [RollbackMutation.delete, .deactivate])
  func failedDeleteOrDeactivateRestoresExactActiveProfile(_ mutation: RollbackMutation) async throws
  {
    let harness = try makeRollbackHarness()
    defer { harness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    let exactPriorBytes = try Data(contentsOf: harness.fileURL)
    harness.sink.failNextAction()

    let result: RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>
    switch mutation {
    case .delete: result = await harness.coordinator.delete(id: original.id)
    case .deactivate: result = await harness.coordinator.deactivate(vendorID: 1118, productID: 654)
    }

    expectRecoveredEngineFailure(result)
    #expect(try Data(contentsOf: harness.fileURL) == exactPriorBytes)
    #expect(try await harness.library.profile(id: original.id) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1118, productID: 654) == original)
    #expect(await harness.router.status(for: device)?.activeProfileID == original.id)
  }

  @Test func oversizedSuccessPayloadRollsBackBeforeReportingFailure() async throws {
    let harness = try await makeHarness(maximumResponseBytes: 1)
    defer { harness.routerHarness.removeFiles() }
    let result = await harness.coordinator.create(profile(name: "Desktop"))

    guard case .failure(let error) = result else {
      Issue.record("Expected response-size rejection.")
      return
    }
    #expect(error.code == .responseTooLarge)
    #expect(try await harness.routerHarness.library.profiles().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: harness.routerHarness.fileURL.path))
  }

  @Test func resetSettingsDoesNotDeleteTheRemappingProfileLibrary() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()

    let libraryURL = harness.routerHarness.fileURL
    #expect(FileManager.default.fileExists(atPath: libraryURL.path))
    let bytesBeforeReset = try Data(contentsOf: libraryURL)

    // The remapping profile library is owned by the coordinator, not by
    // ApplicationServiceServer.resetSettings. The library file must survive any
    // settings reset.
    #expect(FileManager.default.fileExists(atPath: libraryURL.path))
    #expect(try Data(contentsOf: libraryURL) == bytesBeforeReset)
    #expect(try await harness.coordinator.profile(id: original.id).get() == original)
  }

  private func makeHarness(
    postEventProbe: RPCPostEventProbe = RPCPostEventProbe(preflight: [true], requestResult: true),
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes
  ) async throws -> CoordinatorHarness {
    let routerHarness = try await RemappingRouterHarness.make(
      frontmostBundleIdentifier: "com.example.Game",
      accessState: .granted
    )
    let postEventAccess = CoreGraphicsPostEventAccess(probe: postEventProbe)
    return CoordinatorHarness(
      routerHarness: routerHarness,
      coordinator: RemappingRequestCoordinator(
        library: routerHarness.library,
        router: routerHarness.router,
        postEventAccess: postEventAccess,
        maximumResponseBytes: maximumResponseBytes
      )
    )
  }

  private func makeRollbackHarness() throws -> TransactionRollbackHarness {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("profiles.json")
    let library = RemappingProfileLibrary(fileURL: fileURL)
    let recorder = RemappingRouterRecorder()
    let sink = TransactionFaultSink(recorder: recorder)
    let router = RemappingOutputRouter(
      library: library,
      engine: RemappingEventEngine(sink: sink),
      compatibility: RemappingRouterCompatibility(recorder: recorder),
      foregroundApplication: RemappingRouterForeground("com.example.Game"),
      postEventAccess: RemappingRouterAccess(.granted),
      tickerIntervalNanoseconds: nil
    ) { 1_000_000_000 }
    let access = CoreGraphicsPostEventAccess(
      probe: RPCPostEventProbe(preflight: [true], requestResult: true)
    )
    return TransactionRollbackHarness(
      fileURL: fileURL,
      library: library,
      router: router,
      coordinator: RemappingRequestCoordinator(
        library: library,
        router: router,
        postEventAccess: access
      ),
      sink: sink
    )
  }

  private func expectRecoveredEngineFailure(
    _ result: RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>
  ) {
    guard case .failure(let error) = result else {
      Issue.record("Expected a router engine failure.")
      return
    }
    #expect(error.code == .routerEngineUnavailable)
    #expect(error.message == "The system-input sink rejected a remapping action.")
  }

  private func profile(
    id: UUID = UUID(),
    name: String,
    vendorID: UInt16 = 1118,
    productID: UInt16 = 654,
    key: RemappingKeyboardKey = .space
  ) -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: key, modifiers: []))
      ]
    )
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? Int)
  }
}

private struct CoordinatorHarness {
  let routerHarness: RemappingRouterHarness
  let coordinator: RemappingRequestCoordinator
}

enum RollbackMutation: Sendable {
  case deactivate
  case delete
}

private struct TransactionRollbackHarness {
  let fileURL: URL
  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  let coordinator: RemappingRequestCoordinator
  let sink: TransactionFaultSink

  func removeFiles() {
    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
  }
}

private final class TransactionFaultSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private let recorder: RemappingRouterRecorder
  private var pendingFailures = 0

  init(recorder: RemappingRouterRecorder) { self.recorder = recorder }

  func failNextAction() { lock.withLock { pendingFailures += 1 } }

  func send(_ action: RemappingSystemInputAction) throws {
    let shouldFail = lock.withLock { () -> Bool in
      guard pendingFailures > 0 else { return false }
      pendingFailures -= 1
      return true
    }
    guard !shouldFail else { throw RemappingEventEngineError.sinkUnavailable }
    recorder.append(.system(action))
  }
}

private final class RPCPostEventProbe: CoreGraphicsPostEventAccessProbing, @unchecked Sendable {
  private let lock = NSLock()
  private let results: [Bool]
  private let requestResult: Bool
  private var preflightIndex = 0
  private var requests = 0

  var preflightCount: Int { lock.withLock { preflightIndex } }
  var requestCount: Int { lock.withLock { requests } }

  init(preflight: [Bool], requestResult: Bool) {
    results = preflight
    self.requestResult = requestResult
  }

  func preflight() -> Bool {
    lock.withLock {
      defer { preflightIndex += 1 }
      return results[min(preflightIndex, results.count - 1)]
    }
  }

  func request() -> Bool {
    lock.withLock { requests += 1 }
    return requestResult
  }
}
