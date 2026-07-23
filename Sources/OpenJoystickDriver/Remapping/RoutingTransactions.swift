import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  func beginProfileTransaction(
    _ transaction: RemappingProfileTransaction,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    switch profileTransactionState {
    case .inactive:
      profileTransactionState = .active(transaction)
    case .active:
      throw RemappingOutputRoutingError.profileTransactionAlreadyActive
    case .unreconciled(_, let error):
      throw error
    }
    let permit = try requireOperationalPermit(proposedPermit)

    do {
      for identifier in sortedIdentifiers {
        guard let route = routes[identifier] else { continue }
        switch route.selection {
        case .compatibility:
          if route.eligibility == .eligible { notifyCompatibilityStop(identifier) }
        case .remapping, .unavailable:
          try await engine.releaseAll(for: identifier, requiring: permit)
        }
      }
    } catch let error as RemappingEventEngineError {
      if error == .outputSuspended, emissionBarrier.isTerminated {
        throw RemappingOutputRoutingError.shutDown
      }
      recordEngineFailure(error)
      throw RemappingOutputRoutingError.engine(error)
    }
  }

  func acceptProfileTransaction(
    _ transaction: RemappingProfileTransaction,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    try requireActiveProfileTransaction(transaction)
    _ = try requireOperationalPermit(permit)
    try await loadPendingSelections(requiring: permit)
    try await installCurrentRoutes(requiring: permit)
    _ = try requireOperationalPermit(permit)
    profileTransactionState = .inactive
  }

  func rollBackProfileTransaction(
    _ transaction: RemappingProfileTransaction,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    try requireActiveProfileTransaction(transaction)
    _ = try requireOperationalPermit(permit)
    try await reloadAllSelections(requiring: permit)
    try await installCurrentRoutes(requiring: permit)
    _ = try requireOperationalPermit(permit)
    profileTransactionState = .inactive
  }

  func markProfileTransactionUnreconciled(
    _ transaction: RemappingProfileTransaction,
    error: RemappingOutputRoutingError
  ) {
    guard !emissionBarrier.isTerminated else { return }
    guard case .active(let active) = profileTransactionState, active == transaction else { return }
    profileTransactionState = .unreconciled(transaction, error)
    schedulingRevision &+= 1
    markRoutesUnreconciled(error)
  }

  func recoverProfileTransaction(requiring permit: RemappingEmissionPermit?) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    guard case .unreconciled = profileTransactionState else { return }
    _ = try requireOperationalPermit(permit)
    do {
      try await reloadAllSelections(requiring: permit)
      try await installCurrentRoutes(requiring: permit)
      _ = try requireOperationalPermit(permit)
      profileTransactionState = .inactive
    } catch {
      if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
      let routingError = Self.routingError(error)
      if case .unreconciled(let transaction, _) = profileTransactionState {
        profileTransactionState = .unreconciled(transaction, routingError)
      }
      markRoutesUnreconciled(routingError)
      throw routingError
    }
  }

  func profileTransactionPermit() -> RemappingEmissionPermit? {
    switch profileTransactionState {
    case .active(let transaction), .unreconciled(let transaction, _):
      return emissionBarrier.transactionPermit(owner: transaction.id)
    case .inactive:
      return nil
    }
  }

  private func loadPendingSelections(requiring permit: RemappingEmissionPermit?) async throws {
    for identifier in sortedIdentifiers where routes[identifier] == nil {
      _ = try requireOperationalPermit(permit)
      try await loadSelection(for: identifier, requiring: permit)
    }
  }

  private func reloadAllSelections(requiring permit: RemappingEmissionPermit?) async throws {
    let environment = sampleEligibilityEnvironment()
    for identifier in sortedIdentifiers {
      let profile: RemappingProfile?
      do {
        profile = try await library.activeProfile(
          vendorID: identifier.vendorID,
          productID: identifier.productID
        )
      } catch let error as RemappingProfileLibraryError {
        _ = try requireOperationalPermit(permit)
        let routingError = RemappingOutputRoutingError.library(error)
        routes[identifier] = unavailableRoute(routingError, environment: environment)
        throw routingError
      }
      _ = try requireOperationalPermit(permit)
      routes[identifier] = route(
        for: profile.map(RemappingSelectedRoute.remapping) ?? .compatibility,
        environment: environment
      )
    }
  }

  private func installCurrentRoutes(
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    let permit = try requireOperationalPermit(proposedPermit)
    do {
      try await engine.recover(requiring: permit)
    } catch let error as RemappingEventEngineError {
      if error == .outputSuspended, emissionBarrier.isTerminated {
        throw RemappingOutputRoutingError.shutDown
      }
      recordEngineFailure(error)
      throw RemappingOutputRoutingError.engine(error)
    }
    let environment = sampleEligibilityEnvironment()
    await operationCheckpoint(.installRoutes)
    _ = try requireOperationalPermit(proposedPermit)
    for identifier in sortedIdentifiers {
      _ = try requireOperationalPermit(proposedPermit)
      try await reconcileEligibility(
        for: identifier,
        environment: environment,
        requiring: proposedPermit,
        forceOutputState: true
      )
    }
  }

  private func route(
    for selection: RemappingSelectedRoute,
    environment: RemappingEligibilityEnvironment
  ) -> RemappingControllerRoute {
    switch selection {
    case .compatibility:
      let suppressed = controls.outputSuppressed || !controls.compatibilityOutputAllowed
      return RemappingControllerRoute(
        selection: selection,
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: suppressed ? .compatibilityOutputSuppressed : .eligible,
          environment: environment
        ),
        error: nil
      )
    case .remapping(let profile):
      return RemappingControllerRoute(
        selection: selection,
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: RemappingForegroundPolicy.eligibility(
            for: profile.applicationScope,
            frontmostBundleIdentifier: environment.frontmostBundleIdentifier,
            accessState: environment.postEventAccessState,
            outputSuppressed: controls.outputSuppressed
          ),
          environment: environment
        ),
        error: nil
      )
    case .unavailable(let error):
      return unavailableRoute(error, environment: environment)
    }
  }

  private func unavailableRoute(
    _ error: RemappingOutputRoutingError,
    environment: RemappingEligibilityEnvironment
  ) -> RemappingControllerRoute {
    RemappingControllerRoute(
      selection: .unavailable(error),
      eligibilitySnapshot: RemappingEligibilitySnapshot(
        eligibility: .unavailable,
        environment: environment
      ),
      error: error
    )
  }

  private func requireActiveProfileTransaction(
    _ transaction: RemappingProfileTransaction
  ) throws {
    guard case .active(let active) = profileTransactionState, active == transaction else {
      throw RemappingOutputRoutingError.profileTransactionViolation
    }
  }

  func recordUnreconciledRouteIfNeeded(for identifier: DeviceIdentifier) {
    guard case .unreconciled(_, let error) = profileTransactionState else { return }
    routes[identifier] = unavailableRoute(error, environment: sampleEligibilityEnvironment())
  }

  func markRoutesUnreconciled(
    _ error: RemappingOutputRoutingError,
    environment proposedEnvironment: RemappingEligibilityEnvironment? = nil
  ) {
    let environment = proposedEnvironment ?? sampleEligibilityEnvironment()
    for identifier in sortedIdentifiers {
      guard var route = routes[identifier] else {
        routes[identifier] = unavailableRoute(error, environment: environment)
        continue
      }
      route.eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: .unavailable,
        environment: environment
      )
      route.error = error
      routes[identifier] = route
    }
  }

  private static func routingError(_ error: any Error) -> RemappingOutputRoutingError {
    if let error = error as? RemappingOutputRoutingError { return error }
    if let error = error as? RemappingEventEngineError { return .engine(error) }
    if let error = error as? RemappingProfileLibraryError { return .library(error) }
    return .profileTransactionUnreconciled(error.localizedDescription)
  }

}
