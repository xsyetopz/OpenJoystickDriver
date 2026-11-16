import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  /// Opens `transaction` and stops the output of every route, so the profile library can change.
  ///
  /// - Throws: ``RemappingOutputRoutingError/profileTransactionAlreadyActive`` when a transaction
  ///   is active, the failure of an unreconciled transaction, and the first failure to stop a
  ///   route.
  func beginProfileTransaction(
    _ transaction: RemappingProfileTransaction,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    switch profileTransactionState {
    case .inactive: profileTransactionState = .active(transaction)
    case .active: throw RemappingOutputRoutingError.profileTransactionAlreadyActive
    case .unreconciled(_, let error): throw error
    }
    let permit = try requireOperationalPermit(proposedPermit)
    try await cancelAllJoyConPairs(requiring: permit)

    var firstError: (any Error)?
    for identifier in sortedIdentifiers {
      guard let route = routes[identifier] else { continue }
      await engine.endSource(identifier)
      do {
        switch route.selection {
        case .virtualGamepad:
          if route.eligibility == .eligible { await notifyVirtualGamepadStop(identifier) }
        case .remapping(let profile):
          try await releaseAndRetire(for: identifier, profile: profile, requiring: permit)
        case .unavailable: try await releaseAllSafely(for: identifier, requiring: permit)
        }
      } catch { if firstError == nil { firstError = error } }
    }
    if let firstError { throw firstError }
  }

  /// Ends `transaction` by loading the selections that are missing and installing the routes.
  ///
  /// - Throws: ``RemappingOutputRoutingError/profileTransactionViolation`` when `transaction` is
  ///   not the active one.
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

  /// Ends `transaction` by reloading every selection from the library and installing the routes.
  ///
  /// - Throws: ``RemappingOutputRoutingError/profileTransactionViolation`` when `transaction` is
  ///   not the active one.
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

  /// Marks `transaction` as unreconciled with `error` and makes every route unavailable.
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

  /// Reloads the selections and installs the routes after a transaction failed to reconcile.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` that describes the failure; the transaction stays
  ///   unreconciled.
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

  /// Returns the emission permit of the active or unreconciled transaction, or nil when there is
  /// none.
  func profileTransactionPermit() -> RemappingEmissionPermit? {
    switch profileTransactionState {
    case .active(let transaction), .unreconciled(let transaction, _):
      return emissionBarrier.transactionPermit(owner: transaction.id)
    case .inactive: return nil
    }
  }

  /// Loads the selection of every controller that has no route yet.
  private func loadPendingSelections(requiring permit: RemappingEmissionPermit?) async throws {
    for identifier in sortedIdentifiers where routes[identifier] == nil {
      _ = try requireOperationalPermit(permit)
      try await loadSelection(for: identifier, requiring: permit)
    }
  }

  /// Reloads the selection of every controller from the active profiles, in controller order.
  private func reloadAllSelections(requiring permit: RemappingEmissionPermit?) async throws {
    let environment = sampleEligibilityEnvironment()
    for identifier in sortedIdentifiers {
      let profile: RemappingProfile?
      do {
        profile = try await library.activeProfile(
          vendorID: identifier.model.vendorID,
          productID: identifier.model.productID,
          unit: ControllerPortKey.of(identifier, installationKey: installationKey)?.rawValue,
          frontmostAppID: environment.frontmostAppID
        )
      } catch let error as RemappingProfileLibraryError {
        _ = try requireOperationalPermit(permit)
        let routingError = RemappingOutputRoutingError.library(error)
        routes[identifier] = unavailableRoute(routingError, environment: environment)
        throw routingError
      }
      _ = try requireOperationalPermit(permit)
      routes[identifier] = route(
        for: independentSelection(for: profile),
        identifier: identifier,
        environment: environment
      )
    }
  }

  /// Recovers the engine, then reconciles the eligibility of every route and forces its output
  /// state.
  private func installCurrentRoutes(requiring proposedPermit: RemappingEmissionPermit?) async throws
  {
    let permit = try requireOperationalPermit(proposedPermit)
    do { try await engine.recover(requiring: permit) } catch let error as RemappingEventEngineError
    {
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

  /// Returns the route for `selection` with the eligibility computed in `environment`.
  private func route(
    for selection: RemappingSelectedRoute,
    identifier: LogicalControllerID,
    environment: RemappingEligibilityEnvironment
  ) -> RemappingControllerRoute {
    switch selection {
    case .virtualGamepad:
      return RemappingControllerRoute(
        selection: selection,
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: virtualGamepadEligibility,
          environment: environment
        ),
        error: nil
      )
    case .remapping(let profile):
      return RemappingControllerRoute(
        selection: selection,
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: remappingEligibility(profile, for: identifier, environment: environment),
          environment: environment
        ),
        error: nil
      )
    case .unavailable(let error): return unavailableRoute(error, environment: environment)
    }
  }

  /// Returns the route that has no output because of `error`.
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

  /// Throws unless `transaction` is the active one.
  private func requireActiveProfileTransaction(_ transaction: RemappingProfileTransaction) throws {
    guard case .active(let active) = profileTransactionState, active == transaction else {
      throw RemappingOutputRoutingError.profileTransactionViolation
    }
  }

  /// Makes the route of `identifier` unavailable when a transaction is unreconciled.
  func recordUnreconciledRouteIfNeeded(for identifier: LogicalControllerID) {
    guard case .unreconciled(_, let error) = profileTransactionState else { return }
    routes[identifier] = unavailableRoute(error, environment: sampleEligibilityEnvironment())
  }

  /// Makes every route unavailable with `error`.
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

  /// Converts `error` to a routing error; any error of another type becomes an unreconciled
  /// transaction.
  private static func routingError(_ error: any Error) -> RemappingOutputRoutingError {
    if let routing = error as? RemappingOutputRoutingError { return routing }
    if let engine = error as? RemappingEventEngineError { return .engine(engine) }
    if let library = error as? RemappingProfileLibraryError { return .library(library) }
    return .profileTransactionUnreconciled(error.localizedDescription)
  }

}
