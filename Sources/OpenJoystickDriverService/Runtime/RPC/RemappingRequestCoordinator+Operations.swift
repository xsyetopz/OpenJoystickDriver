import Foundation
import OpenJoystickDriverKit

extension RemappingRequestCoordinator {
  /// Returns the profiles, active profiles, routes, Joy-Con pairs and issues as one snapshot.
  func snapshot() async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await exclusively { try await makeSnapshot() }
  }

  /// Runs the motion calibration `command` on the controller that `arguments` names.
  func motionCalibration(
    _ arguments: ApplicationServiceMotionCalibrationArguments
  ) async -> RemappingRequestResult<RemappingMotionCalibrationStatus> {
    await exclusively {
      let connected = await connectedControllers()
      guard let controller = try? arguments.controller.resolve(in: connected) else {
        throw RemappingMotionCalibrationError.controllerUnavailable
      }
      let status = try await router.motionCalibration(
        for: controller.logicalControllerID,
        command: arguments.command
      )
      try ensurePayloadFits(status)
      return status
    }
  }

  /// Pairs the two Joy-Con controllers under the profile and returns the snapshot.
  func pairJoyCons(
    _ arguments: ApplicationServiceJoyConPairArguments
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await changing {
      let connected = await connectedControllers()
      guard let left = try? arguments.left.resolve(in: connected),
        let right = try? arguments.right.resolve(in: connected)
      else { throw RemappingJoyConPairError.controllerUnavailable }
      guard let profile = try await library.profile(id: arguments.profileID) else {
        throw RemappingProfileLibraryError.profileNotFound(arguments.profileID)
      }
      _ = try await router.pairJoyCons(
        left: left.logicalControllerID,
        right: right.logicalControllerID,
        profile: profile
      )
      return try await makeSnapshot()
    }
  }

  /// Ends the Joy-Con pair session and returns the snapshot.
  func unpairJoyCons(
    _ arguments: ApplicationServiceJoyConUnpairArguments
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await changing {
      try await router.unpairJoyCons(arguments.sessionID)
      return try await makeSnapshot()
    }
  }

  /// Returns the profile `id`, or a profile-not-found error.
  func profile(id: UUID) async -> RemappingRequestResult<RemappingProfile> {
    await exclusively {
      guard let profile = try await library.profile(id: id) else {
        throw RemappingProfileLibraryError.profileNotFound(id)
      }
      try ensurePayloadFits(profile)
      return profile
    }
  }

  /// Adds `profile` to the library and returns the snapshot.
  func create(
    _ profile: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate { try await library.create(profile) }
  }

  /// Replaces the profile if the stored one equals `expectedCurrent`, and returns the snapshot.
  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate(
      preflight: { try await library.requireCurrent(expectedCurrent, profileID: profile.id) },
      operation: { try await library.update(profile, expectedCurrent: expectedCurrent) }
    )
  }

  /// Adds `profile` as an imported profile and returns the snapshot.
  func importProfile(
    _ profile: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate { try await library.importProfile(profile) }
  }

  /// Deletes the profile `id` and returns the snapshot.
  func delete(id: UUID) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>
  { await mutate { try await library.delete(id: id) } }

  /// Deletes the damaged profile of the issue `issueID` and returns the snapshot.
  func deleteDamagedProfile(
    issueID: UUID
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await changing {
      _ = try await library.deleteDamagedProfile(issueID: issueID)
      return try await makeSnapshot()
    }
  }

  /// Resets the damaged library of the issue `issueID` and returns the snapshot.
  func resetDamagedLibrary(
    issueID: UUID
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await changing {
      _ = try await library.resetDamagedLibrary(issueID: issueID)
      return try await makeSnapshot()
    }
  }

  /// Reloads the profile files and refreshes each model whose active profiles changed.
  func reloadProfiles() async -> RemappingRequestResult<Void> {
    await changing {
      for model in Self.sorted(try await library.reload()) {
        do {
          try await router.refreshModel(vendorID: model.vendorID, productID: model.productID)
        } catch {
          fputs(
            "[Profiles] Cannot refresh \(model.vendorID):\(model.productID): "
              + "\(error.localizedDescription)\n",
            stderr
          )
        }
      }
    }
  }

  /// Activates the profile `id` for its model; `allowEmpty` lets a profile that produces no output
  /// activate.
  func activate(
    id: UUID,
    allowEmpty: Bool
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate { try await library.activate(profileID: id, allowEmpty: allowEmpty) }
  }

  /// Deactivates every profile of the model and returns the snapshot.
  func deactivate(
    vendorID: UInt16,
    productID: UInt16
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate { try await library.deactivateAll(vendorID: vendorID, productID: productID) }
  }

  /// Deactivates the profile `profileID` and returns the snapshot.
  func deactivate(
    profileID: UUID
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate { try await library.deactivate(profileID: profileID) }
  }

  /// Returns the state of the access to post system input events.
  func currentPostEventAccess() async -> RemappingRequestResult<RemappingPostEventAccessState> {
    await exclusively { postEventAccess.currentState() }
  }

  /// Requests the access to post system input events and refreshes route eligibility.
  func requestPostEventAccess() async -> RemappingRequestResult<RemappingPostEventAccessState> {
    await changing {
      let state = postEventAccess.requestAccess()
      try await router.refreshEligibility()
      return state
    }
  }

  /// Applies a library change as one transaction on the library and the routes.
  ///
  /// A failure rolls the library and the routes back and is reported as the original error.
  ///
  /// - Parameters:
  ///   - preflight: Checks the request before the library changes.
  ///   - operation: Changes the library and returns the models that need a refresh.
  /// - Returns: The result of the request, with the snapshot of the remapping state.
  private func mutate(
    preflight: @Sendable () async throws -> Void = {},
    operation: () async throws -> RemappingProfileMutationImpact
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await changing {
      try await preflight()
      let checkpoint = try await library.checkpoint()
      let transaction = try await router.beginProfileTransaction()
      do {
        try Task.checkCancellation()
        let impact = try await operation()
        for model in Self.sorted(impact.modelsNeedingRefresh) {
          try await router.refreshModel(vendorID: model.vendorID, productID: model.productID)
        }
        let payload = try await makeSnapshot(validateResponse: false)
        try await beforeMutationResponseAcceptance(payload)
        try Task.checkCancellation()
        try ensurePayloadFits(payload)
        try await router.acceptProfileTransaction(transaction)
        return payload
      } catch {
        let original = Self.rpcError(error)
        try await rollBack(checkpoint: checkpoint, transaction: transaction, original: original)
        throw original
      }
    }
  }

  /// Builds the snapshot of the library and the router.
  ///
  /// When `validateResponse` is set, the payload must fit the response limits.
  ///
  /// - Throws: ``RemappingProfileLibraryError/corruptLibrary`` when an active profile is missing,
  ///   or ``ApplicationServiceRemappingRPCError`` when the payload does not fit.
  private func makeSnapshot(
    validateResponse: Bool = true
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    let librarySnapshot = try await library.snapshot()
    let profilesByID = Dictionary(
      uniqueKeysWithValues: librarySnapshot.profiles.map { ($0.id, $0) }
    )
    let activeProfiles = try librarySnapshot.activeProfiles.map { active in
      guard let profile = profilesByID[active.profileID] else {
        throw RemappingProfileLibraryError.corruptLibrary
      }
      return ApplicationServiceRemappingActiveProfilePayload(
        vendorID: active.model.vendorID,
        productID: active.model.productID,
        profileID: profile.id,
        profileName: profile.name,
        applicationScope: active.applicationScope ?? profile.applicationScope
      )
    }
    // Only the package profiles this snapshot lists, should a reload land between the two reads.
    let packageProfiles = try await library.packageProfileSources()
      .filter { profilesByID[$0.key] != nil }
      .map { ApplicationServiceRemappingPackageProfile(profileID: $0.key, package: $0.value) }
      .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
    let lastUsed = librarySnapshot.lastUsed
      .filter { profilesByID[$0.key] != nil }
      .map { ApplicationServiceRemappingProfileUse(profileID: $0.key, usedAt: $0.value) }
      .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
    let routerSnapshot = await router.statusSnapshot()
    // A controller that disconnected since the router last saw it has no token and is left out.
    let tokens = Dictionary(
      uniqueKeysWithValues: await connectedControllers().map {
        ($0.logicalControllerID, $0.sessionToken)
      }
    )
    let routes = routerSnapshot.routes.compactMap { status in
      tokens[status.identifier].map { Self.routePayload(status, sessionToken: $0) }
    }
    let joyConPairs = routerSnapshot.joyConPairs.compactMap { session in
      Self.joyConPairPayload(session, tokens: tokens)
    }
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: librarySnapshot.profiles,
      activeProfiles: activeProfiles,
      routes: routes,
      joyConPairs: joyConPairs,
      profileIssues: librarySnapshot.issues,
      packageProfiles: packageProfiles,
      lastUsed: lastUsed,
      postEventAccess: routerSnapshot.postEventAccessState
    )
    if validateResponse { try ensurePayloadFits(payload) }
    return payload
  }

  /// Restores the library and the routes to their state before a failed mutation.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` with the unreconciled code when either
  ///   restoration fails.
  private func rollBack(
    checkpoint: RemappingProfileLibraryCheckpoint,
    transaction: RemappingProfileTransaction,
    original: ApplicationServiceRemappingRPCError
  ) async throws {
    do { try await library.restore(checkpoint) } catch {
      let unreconciled = Self.unreconciledError(
        original: original,
        detail: "The prior profiles could not be restored: \(error.localizedDescription)"
      )
      await router.markProfileTransactionUnreconciled(transaction, detail: unreconciled.message)
      throw unreconciled
    }

    do { try await router.rollBackProfileTransaction(transaction) } catch {
      throw Self.unreconciledError(
        original: original,
        detail: "The prior profiles were restored, but route reconciliation failed: "
          + error.localizedDescription
      )
    }
  }

  /// Checks that `value` and its response frame fit the response limits.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when encoding fails or a limit is exceeded.
  private func ensurePayloadFits<Value: Encodable>(_ value: Value) throws {
    let encoded: Data
    do { encoded = try JSONEncoder().encode(value) } catch {
      throw ApplicationServiceRemappingRPCError(
        code: .responseEncodingFailed,
        message: "The remapping RPC response could not be encoded."
      )
    }
    guard encoded.count <= maximumResponseBytes else {
      throw ApplicationServiceRemappingRPCError(
        code: .responseTooLarge,
        message: "The remapping RPC response exceeds the service limit."
      )
    }
    let response = LocalServiceRPCResponse(result: encoded, error: nil)
    let framed: Data
    do { framed = try JSONEncoder().encode(response) } catch {
      throw ApplicationServiceRemappingRPCError(
        code: .responseEncodingFailed,
        message: "The remapping RPC response could not be encoded."
      )
    }
    guard framed.count <= maximumTransportFrameBytes else {
      throw ApplicationServiceRemappingRPCError(
        code: .responseTooLarge,
        message: "The remapping RPC response exceeds the transport frame limit."
      )
    }
  }

  /// Runs `operation` like ``exclusively(_:)`` and announces a status change when it succeeds.
  private func changing<Value: Sendable>(
    _ operation: () async throws -> Value
  ) async -> RemappingRequestResult<Value> {
    let result = await exclusively(operation)
    if case .success = result { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Runs `operation` after every earlier operation and captures its outcome.
  private func exclusively<Value: Sendable>(
    _ operation: () async throws -> Value
  ) async -> RemappingRequestResult<Value> {
    let predecessor = operationTail?.task
    let operationID = UUID()
    let signal = AsyncStream<Void>.makeStream()
    let current = Task {
      if let predecessor { await predecessor.value }
      for await _ in signal.stream {}
    }
    operationTail = (operationID, current)
    if let predecessor { await predecessor.value }
    defer {
      signal.continuation.finish()
      if operationTail?.id == operationID { operationTail = nil }
    }
    return await capture(operation)
  }

  /// Returns the value of `operation` or the RPC error that maps its failure.
  private func capture<Value: Sendable>(
    _ operation: () async throws -> Value
  ) async -> RemappingRequestResult<Value> {
    do { return .success(try await operation()) } catch { return .failure(Self.rpcError(error)) }
  }

  /// Returns `models` ordered by vendor ID, then product ID.
  private static func sorted(_ models: Set<RemappingProfileModel>) -> [RemappingProfileModel] {
    models.sorted { ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID) }
  }

  /// Returns the payload of a Joy-Con pair, or nil when its profile has no pair settings or a
  /// member has no session token.
  private static func joyConPairPayload(
    _ session: RemappingJoyConPairSession,
    tokens: [LogicalControllerID: ControllerSessionToken]
  ) -> ApplicationServiceJoyConPairPayload? {
    guard let settings = session.profile.joyConPair, let left = tokens[session.left],
      let right = tokens[session.right]
    else { return nil }
    return ApplicationServiceJoyConPairPayload(
      sessionID: session.id,
      left: left,
      right: right,
      profileID: session.profile.id,
      profileName: session.profile.name,
      gyroSelection: settings.gyroSelection
    )
  }

  /// Returns the payload of a route for the controller session `sessionToken`.
  private static func routePayload(
    _ status: RemappingRouteStatus,
    sessionToken: ControllerSessionToken
  ) -> ApplicationServiceRemappingRoutePayload {
    let selection: ApplicationServiceRemappingRouteSelection
    switch status.selection {
    case .virtualGamepad: selection = .virtualGamepad
    case .remapping: selection = .remapping
    case .unavailable: selection = .unavailable
    }
    let failure = status.error.map {
      let error = rpcError($0)
      return ApplicationServiceRemappingFailurePayload(code: error.code, message: error.message)
    }
    return ApplicationServiceRemappingRoutePayload(
      vendorID: status.identifier.model.vendorID,
      productID: status.identifier.model.productID,
      sessionToken: sessionToken,
      selection: selection,
      eligibility: routeEligibility(status.eligibility),
      activeProfileID: status.activeProfileID,
      activeProfileName: status.activeProfileName,
      applicationScope: status.applicationScope,
      frontmostAppID: status.frontmostAppID,
      postEventAccess: status.postEventAccessState,
      failure: failure
    )
  }

  /// Maps a routing eligibility to its RPC value.
  private static func routeEligibility(
    _ eligibility: RemappingRouteEligibility
  ) -> ApplicationServiceRemappingRouteEligibility {
    switch eligibility {
    case .eligible: .eligible
    case .outputSuppressed: .outputSuppressed
    case .postEventAccessNotAuthorized: .postEventAccessNotAuthorized
    case .targetApplicationNotFrontmost: .targetApplicationNotFrontmost
    case .physicalInputNotExclusive: .physicalInputNotExclusive
    case .unavailable: .unavailable
    case .virtualOutputSuppressed: .virtualOutputSuppressed
    }
  }
}
