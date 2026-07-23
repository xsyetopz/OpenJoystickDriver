import Foundation
import OpenJoystickDriverKit

typealias RemappingRequestResult<Value: Sendable> = Result<
  Value,
  ApplicationServiceRemappingRPCError
>

/// Serializes profile mutations, route refreshes, and the snapshot returned to RPC clients.
actor RemappingRequestCoordinator {
  typealias MutationResponseAcceptanceHook = @Sendable (
    ApplicationServiceRemappingSnapshotPayload
  ) async throws -> Void

  private let library: RemappingProfileLibrary
  private let router: RemappingOutputRouter
  private let postEventAccess: CoreGraphicsPostEventAccess
  private let maximumResponseBytes: Int
  private let maximumTransportFrameBytes: Int
  private let beforeMutationResponseAcceptance: MutationResponseAcceptanceHook
  private var operationTail: (id: UUID, task: Task<Void, Never>)?

  init(
    library: RemappingProfileLibrary,
    router: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess,
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes,
    maximumTransportFrameBytes: Int = ApplicationServiceRemappingRPC
      .maximumTransportFrameBytes,
    beforeMutationResponseAcceptance: @escaping MutationResponseAcceptanceHook = { _ in }
  ) {
    self.library = library
    self.router = router
    self.postEventAccess = postEventAccess
    self.maximumResponseBytes = maximumResponseBytes
    self.maximumTransportFrameBytes = maximumTransportFrameBytes
    self.beforeMutationResponseAcceptance = beforeMutationResponseAcceptance
  }

  func snapshot() async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await exclusively { try await makeSnapshot() }
  }

  func profile(id: UUID) async -> RemappingRequestResult<RemappingProfile> {
    await exclusively {
      guard let profile = try await library.profile(id: id) else {
        throw RemappingProfileLibraryError.profileNotFound(id)
      }
      try ensurePayloadFits(profile)
      return profile
    }
  }

  func create(
    _ profile: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate {
      try await library.create(profile)
    }
  }

  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate(
      preflight: {
        try await library.requireCurrent(expectedCurrent, profileID: profile.id)
      },
      operation: {
        try await library.update(profile, expectedCurrent: expectedCurrent)
      }
    )
  }

  func importProfile(
    _ profile: RemappingProfile
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate {
      try await library.importProfile(profile)
    }
  }

  func delete(
    id: UUID
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate {
      try await library.delete(id: id)
    }
  }

  func activate(
    id: UUID
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate {
      try await library.activate(profileID: id)
    }
  }

  func deactivate(
    vendorID: UInt16,
    productID: UInt16
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await mutate {
      try await library.deactivate(vendorID: vendorID, productID: productID)
    }
  }

  func currentPostEventAccess() async -> RemappingRequestResult<RemappingPostEventAccessState> {
    await exclusively { postEventAccess.currentState() }
  }

  func requestPostEventAccess() async -> RemappingRequestResult<RemappingPostEventAccessState> {
    await exclusively {
      let state = postEventAccess.requestAccess()
      try await router.refreshEligibility()
      return state
    }
  }

  private func mutate(
    preflight: @Sendable () async throws -> Void = {},
    operation: () async throws -> RemappingProfileMutationImpact
  ) async -> RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload> {
    await exclusively {
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
        try await rollBack(
          checkpoint: checkpoint,
          transaction: transaction,
          original: original
        )
        throw original
      }
    }
  }

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
        applicationScope: profile.applicationScope
      )
    }
    let routerSnapshot = await router.statusSnapshot()
    let routes = routerSnapshot.routes.map(Self.routePayload)
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: librarySnapshot.profiles,
      activeProfiles: activeProfiles,
      routes: routes,
      postEventAccess: routerSnapshot.postEventAccessState
    )
    if validateResponse { try ensurePayloadFits(payload) }
    return payload
  }

  private func rollBack(
    checkpoint: RemappingProfileLibraryCheckpoint,
    transaction: RemappingProfileTransaction,
    original: ApplicationServiceRemappingRPCError
  ) async throws {
    do {
      try await library.restore(checkpoint)
    } catch {
      let unreconciled = Self.unreconciledError(
        original: original,
        detail: "The prior profile library could not be restored: \(error.localizedDescription)"
      )
      await router.markProfileTransactionUnreconciled(
        transaction,
        detail: unreconciled.message
      )
      throw unreconciled
    }

    do {
      try await router.rollBackProfileTransaction(transaction)
    } catch {
      throw Self.unreconciledError(
        original: original,
        detail: "The prior profile library was restored, but route reconciliation failed: "
          + error.localizedDescription
      )
    }
  }

  private func ensurePayloadFits<Value: Encodable>(_ value: Value) throws {
    let encoded: Data
    do {
      encoded = try JSONEncoder().encode(value)
    } catch {
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
    do {
      framed = try JSONEncoder().encode(response)
    } catch {
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

  private func capture<Value: Sendable>(
    _ operation: () async throws -> Value
  ) async -> RemappingRequestResult<Value> {
    do {
      return .success(try await operation())
    } catch {
      return .failure(Self.rpcError(error))
    }
  }

  private static func sorted(
    _ models: Set<RemappingProfileModel>
  ) -> [RemappingProfileModel] {
    models.sorted {
      ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID)
    }
  }

  private static func routePayload(_ status: RemappingRouteStatus)
    -> ApplicationServiceRemappingRoutePayload
  {
    let selection: ApplicationServiceRemappingRouteSelection
    switch status.selection {
    case .compatibility: selection = .compatibility
    case .remapping: selection = .remapping
    case .unavailable: selection = .unavailable
    }
    let failure = status.error.map {
      let error = rpcError($0)
      return ApplicationServiceRemappingFailurePayload(code: error.code, message: error.message)
    }
    return ApplicationServiceRemappingRoutePayload(
      vendorID: status.identifier.vendorID,
      productID: status.identifier.productID,
      runtimeIdentifier: status.identifier.runtimeIdentifier,
      selection: selection,
      eligibility: routeEligibility(status.eligibility),
      activeProfileID: status.activeProfileID,
      activeProfileName: status.activeProfileName,
      applicationScope: status.applicationScope,
      frontmostBundleIdentifier: status.frontmostBundleIdentifier,
      postEventAccess: status.postEventAccessState,
      failure: failure
    )
  }

  private static func routeEligibility(_ eligibility: RemappingRouteEligibility)
    -> ApplicationServiceRemappingRouteEligibility
  {
    switch eligibility {
    case .compatibilityOutputSuppressed: .compatibilityOutputSuppressed
    case .eligible: .eligible
    case .outputSuppressed: .outputSuppressed
    case .postEventAccessNotAuthorized: .postEventAccessNotAuthorized
    case .targetApplicationNotFrontmost: .targetApplicationNotFrontmost
    case .unavailable: .unavailable
    }
  }

  static func rpcError(_ error: any Error) -> ApplicationServiceRemappingRPCError {
    if let error = error as? ApplicationServiceRemappingRPCError { return error }
    if let error = error as? RemappingProfileLibraryError {
      return libraryError(error)
    }
    if let error = error as? RemappingOutputRoutingError {
      return routingError(error)
    }
    return ApplicationServiceRemappingRPCError(
      code: .unexpected,
      message: error.localizedDescription
    )
  }

  private static func unreconciledError(
    original: ApplicationServiceRemappingRPCError,
    detail: String
  ) -> ApplicationServiceRemappingRPCError {
    ApplicationServiceRemappingRPCError(
      code: .transactionUnreconciled,
      message: "Remapping mutation failed [\(original.code.rawValue)]: "
        + "\(original.message) \(detail)"
    )
  }

  private static func libraryError(
    _ error: RemappingProfileLibraryError
  ) -> ApplicationServiceRemappingRPCError {
    let code: ApplicationServiceRemappingRPCError.Code
    switch error {
    case .corruptLibrary: code = .corruptLibrary
    case .duplicateName: code = .duplicateName
    case .invalidProfile: code = .invalidProfile
    case .librarySizeExceeded: code = .librarySizeExceeded
    case .profileCountExceeded: code = .profileCountExceeded
    case .profileAlreadyExists: code = .profileAlreadyExists
    case .profileNotFound: code = .profileNotFound
    case .profileUpdateConflict: code = .profileUpdateConflict
    case .unreadableLibrary: code = .unreadableLibrary
    case .unsupportedLibraryVersion: code = .unsupportedLibraryVersion
    case .unwritableLibrary: code = .unwritableLibrary
    }
    return ApplicationServiceRemappingRPCError(
      code: code,
      message: error.localizedDescription
    )
  }

  private static func routingError(
    _ error: RemappingOutputRoutingError
  ) -> ApplicationServiceRemappingRPCError {
    let code: ApplicationServiceRemappingRPCError.Code
    switch error {
    case .engine: code = .routerEngineUnavailable
    case .library: code = .routerLibraryUnavailable
    case .libraryAndEngine: code = .routerLibraryAndEngineUnavailable
    case .profileTransactionAlreadyActive,
      .profileTransactionUnreconciled,
      .profileTransactionViolation:
      code = .transactionUnreconciled
    case .shutDown: code = .routerShutDown
    }
    return ApplicationServiceRemappingRPCError(
      code: code,
      message: error.localizedDescription
    )
  }
}
