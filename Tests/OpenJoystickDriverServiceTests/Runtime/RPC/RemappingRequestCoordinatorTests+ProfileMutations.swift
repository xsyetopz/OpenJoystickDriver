import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension RemappingRequestCoordinatorTests {
  @Test
  func pairingMutationUsesLibraryProfileAndReturnsTheAuthoritativeSessionSnapshot() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let profile = RemappingProfile(
      name: "Pair",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
      applicationScope: .global,
      joyConPair: RemappingJoyConPairSettings(gyroSelection: .left),
      bindings: []
    )
    _ = try await harness.coordinator.create(profile).get()
    let automaticActivation = await harness.coordinator.activate(id: profile.id)
    guard case .failure(let activationError) = automaticActivation else {
      Issue.record("Expected pair profiles to require an explicit session.")
      return
    }
    #expect(activationError.code == .invalidArguments)
    let left = remappingRouterDevice(1, vendorID: 0x057E, productID: 0x2006)
    let right = remappingRouterDevice(2, vendorID: 0x057E, productID: 0x2007)
    try await harness.routerHarness.router.dispatchCausally(.activation, from: left)
    try await harness.routerHarness.router.dispatchCausally(.activation, from: right)

    var snapshot = try await harness.coordinator.pairJoyCons(
      .init(
        leftRuntimeIdentifier: left.runtimeIdentifier,
        rightRuntimeIdentifier: right.runtimeIdentifier,
        profileID: profile.id
      )
    ).get()
    let session = try #require(snapshot.joyConPairs.first)
    #expect(session.profileID == profile.id)
    #expect(session.gyroSelection == .left)

    snapshot = try await harness.coordinator.unpairJoyCons(.init(sessionID: session.sessionID))
      .get()
    #expect(snapshot.joyConPairs.isEmpty)
  }

  @Test
  func fullCRUDImportActivationAndDeactivationUseOneServiceOwnedLibrary() async throws {
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

  @Test


  func activeUpdateAndDeleteReleaseHeldStateBeforeSuccess() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop", key: .space)
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(
      changes: [.press(.faceSouth)],
      from: device
    )

    let updated = profile(id: original.id, name: "Desktop", key: .b)

    _ = try await harness.coordinator.update(updated, expectedCurrent: original).get()
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)),
      ]
    )

    try await harness.routerHarness.router.dispatchCausally(
      changes: [.press(.faceSouth)],
      from: device
    )
    _ = try await harness.coordinator.delete(id: updated.id).get()
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.b)),
        .system(.keyUp(.b)),
      ]
    )
    #expect(await harness.routerHarness.router.status(for: device)?.selection == .virtualGamepad)
  }

  @Test
  func staleSecondClientReceivesTypedConflictWithoutMutationOrOutputDrain() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }

    let original = profile(name: "Desktop", key: .space)
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(
      changes: [.press(.faceSouth)],
      from: device
    )

    harness.routerHarness.recorder.removeAll()

    let firstUpdate = profile(id: original.id, name: "Desktop", key: .a)
    _ = try await harness.coordinator.update(firstUpdate, expectedCurrent: original).get()
    harness.routerHarness.recorder.removeAll()
    let bytesAfterFirstUpdate = try libraryFiles(in: harness.routerHarness.directory)
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
    #expect(try libraryFiles(in: harness.routerHarness.directory) == bytesAfterFirstUpdate)
    #expect(try await harness.routerHarness.library.profile(id: original.id) == firstUpdate)
    #expect(await harness.routerHarness.router.status(for: device) == routeAfterFirstUpdate)
    #expect(harness.routerHarness.recorder.snapshot().isEmpty)
  }

  @Test
  func movingAnActiveProfileRefreshesItsFormerModelAndClearsSelection() async throws {
    let harness = try await makeHarness()

    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let device = remappingRouterDevice(1)
    try await harness.routerHarness.router.dispatchCausally(

      changes: [.press(.faceSouth)],
      from: device
    )

    let moved = profile(id: original.id, name: "Desktop", vendorID: 1356, productID: 2508)
    let snapshot = try await harness.coordinator.update(moved, expectedCurrent: original).get()

    #expect(snapshot.activeProfiles.isEmpty)
    #expect(
      harness.routerHarness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)),
      ]
    )
    #expect(await harness.routerHarness.router.status(for: device)?.selection == .virtualGamepad)
  }

  @Test
  func snapshotPreservesExactSameModelRoutesWithoutSerialNumbers() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let mapped = profile(name: "Desktop")
    _ = try await harness.coordinator.create(mapped).get()
    _ = try await harness.coordinator.activate(id: mapped.id).get()
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)
    try await harness.routerHarness.router.dispatchCausally(.activation, from: first)
    try await harness.routerHarness.router.dispatchCausally(.activation, from: second)

    let snapshot = try await harness.coordinator.snapshot().get()
    #expect(snapshot.routes.count == 2)
    #expect(
      Set(snapshot.routes.map(\.runtimeIdentifier)) == [
        first.runtimeIdentifier, second.runtimeIdentifier,
      ]
    )
    #expect(snapshot.routes.allSatisfy { $0.selection == .remapping })
    #expect(snapshot.routes.allSatisfy { $0.activeProfileID == mapped.id })
    let encoded = try #require(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
    #expect(!encoded.contains("serial"))
  }

  @Test
  func permissionRequestReturnsAuthoritativePreflightReadbackWithoutTrustingRequestResult()
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

  @Test
  func corruptStoreAndRouterFailuresCrossAsStableTypedErrors() async throws {
    let corruptHarness = try await makeHarness()
    defer { corruptHarness.routerHarness.removeFiles() }
    try Data("not json".utf8).write(to: corruptHarness.routerHarness.library.selectionsURL)
    let corrupt = try await corruptHarness.coordinator.snapshot().get()
    #expect(corrupt.profiles.isEmpty)
    #expect(corrupt.profileIssues.count == 1)
    #expect(corrupt.profileIssues.first?.kind == .unusableLibrary)

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
    #expect(
      try await stoppedHarness.routerHarness.library.activeProfile(vendorID: 1118, productID: 654)
        == nil
    )
  }

  @Test


  func failedActiveModelMoveRestoresExactLibraryAndBothRoutes() async throws {
    let harness = try makeRollbackHarness()
    defer { harness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()
    _ = try await harness.coordinator.activate(id: original.id).get()
    let oldDevice = remappingRouterDevice(1)
    let newDevice = remappingRouterDevice(2, vendorID: 1356, productID: 2508)

    try await harness.router.dispatchCausally(.activation, from: newDevice)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: oldDevice)
    let exactPriorBytes = try libraryFiles(in: harness.directory)
    let profileURL = harness.library.profileURL(original.id)
    let priorFilePermissions = try permissions(at: profileURL)
    let priorParentPermissions = try permissions(at: harness.directory)
    harness.sink.failNextAction()

    let moved = profile(id: original.id, name: original.name, vendorID: 1356, productID: 2508)
    let result = await harness.coordinator.update(moved, expectedCurrent: original)

    expectRecoveredEngineFailure(result)
    #expect(try libraryFiles(in: harness.directory) == exactPriorBytes)
    #expect(try permissions(at: profileURL) == priorFilePermissions)
    #expect(try permissions(at: harness.directory) == priorParentPermissions)
    #expect(try await harness.library.profile(id: original.id) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1118, productID: 654) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1356, productID: 2508) == nil)
    #expect(await harness.router.status(for: oldDevice)?.activeProfileID == original.id)
    #expect(await harness.router.status(for: newDevice)?.selection == .virtualGamepad)
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
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    let exactPriorBytes = try libraryFiles(in: harness.directory)
    harness.sink.failNextAction()

    let result: RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>
    switch mutation {
    case .delete: result = await harness.coordinator.delete(id: original.id)
    case .deactivate: result = await harness.coordinator.deactivate(vendorID: 1118, productID: 654)
    }

    expectRecoveredEngineFailure(result)
    #expect(try libraryFiles(in: harness.directory) == exactPriorBytes)
    #expect(try await harness.library.profile(id: original.id) == original)
    #expect(try await harness.library.activeProfile(vendorID: 1118, productID: 654) == original)
    #expect(await harness.router.status(for: device)?.activeProfileID == original.id)
  }

  @Test
  func oversizedSuccessPayloadRollsBackBeforeReportingFailure() async throws {
    let harness = try await makeHarness(maximumResponseBytes: 1)
    defer { harness.routerHarness.removeFiles() }
    let result = await harness.coordinator.create(profile(name: "Desktop"))

    guard case .failure(let error) = result else {
      Issue.record("Expected response-size rejection.")
      return
    }
    #expect(error.code == .responseTooLarge)
    #expect(try await harness.routerHarness.library.profiles().isEmpty)
    #expect(try libraryFiles(in: harness.routerHarness.directory).isEmpty)
  }

  @Test
  func resetSettingsDoesNotDeleteTheRemappingProfileLibrary() async throws {
    let harness = try await makeHarness()
    defer { harness.routerHarness.removeFiles() }
    let original = profile(name: "Desktop")
    _ = try await harness.coordinator.create(original).get()

    let directory = harness.routerHarness.directory
    let bytesBeforeReset = try libraryFiles(in: directory)
    #expect(!bytesBeforeReset.isEmpty)

    // The remapping profile library is owned by the coordinator, not by
    // ApplicationServiceServer.resetSettings. The library file must survive any
    // settings reset.
    #expect(try libraryFiles(in: directory) == bytesBeforeReset)
    #expect(try await harness.coordinator.profile(id: original.id).get() == original)
  }

}
