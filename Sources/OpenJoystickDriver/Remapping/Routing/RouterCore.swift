import Foundation
import OpenJoystickDriverKit

actor RemappingRoutingCore {
  let library: RemappingProfileLibrary
  let engine: RemappingEventEngine
  let compatibility: any OutputDispatcher
  let foregroundApplication: any RemappingForegroundApplicationProviding
  let postEventAccess: any RemappingPostEventAccessProviding
  let operationCheckpoint: @Sendable (RemappingRoutingCheckpoint) async -> Void
  var emissionBarrier: RemappingEmissionBarrier { engine.emissionBarrier }
  var controls = RemappingRoutingControls(
    outputSuppressed: false,
    compatibilityOutputAllowed: true,
    revision: 0
  )
  var routes: [DeviceIdentifier: RemappingControllerRoute] = [:]
  var connectedIdentifiers: Set<DeviceIdentifier> = []
  var profileTransactionState = RemappingProfileTransactionState.inactive
  var terminationRequested = false
  private var terminalCleanupComplete = false
  var schedulingRevision: UInt64 = 0

  init(
    library: RemappingProfileLibrary,
    engine: RemappingEventEngine,
    compatibility: any OutputDispatcher,
    foregroundApplication: any RemappingForegroundApplicationProviding,
    postEventAccess: any RemappingPostEventAccessProviding,
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void
  ) {
    self.library = library
    self.engine = engine
    self.compatibility = compatibility
    self.foregroundApplication = foregroundApplication
    self.postEventAccess = postEventAccess
    self.operationCheckpoint = operationCheckpoint
  }

  func apply(
    _ proposed: RemappingRoutingControls,
    requiring permit: RemappingEmissionPermit?,
    refreshEligibilityWhenUnchanged: Bool = false
  ) async throws {
    defer { schedulingRevision &+= 1 }
    _ = try requireOperationalPermit(permit)
    guard proposed.revision >= controls.revision else { return }
    let previousCompatibilitySuppressed = compatibilityIsSuppressed
    let outputSuppressionChanged = proposed.outputSuppressed != controls.outputSuppressed
    let compatibilityEligibilityChanged =
      proposed.compatibilityOutputAllowed != controls.compatibilityOutputAllowed
    controls = proposed
    await operationCheckpoint(.apply)
    _ = try requireOperationalPermit(permit)
    if case .unreconciled = profileTransactionState { return }
    let compatibilityBecameSuppressed =
      !previousCompatibilitySuppressed && compatibilityIsSuppressed
    if compatibilityBecameSuppressed && !profileTransactionState.blocksOutput {
      for identifier in sortedIdentifiers {
        guard case .compatibility = routes[identifier]?.selection else { continue }
        await notifyCompatibilityStop(identifier)
      }
    }
    guard
      outputSuppressionChanged || compatibilityEligibilityChanged || refreshEligibilityWhenUnchanged
    else { return }
    try await refreshEligibility(requiring: permit)
  }

  func dispatch(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    connectedIdentifiers.insert(identifier)
    guard !profileTransactionState.blocksOutput else {
      recordUnreconciledRouteIfNeeded(for: identifier)
      return
    }
    if routes[identifier] == nil {
      try await loadSelection(for: identifier, requiring: proposedPermit)
    }
    try await reconcileEligibility(for: identifier, requiring: proposedPermit)
    await operationCheckpoint(.dispatch)
    guard let route = routes[identifier] else { return }
    switch route.selection {
    case .compatibility:
      guard route.eligibility == .eligible else { return }
      _ = try requireOperationalPermit(proposedPermit)
      await compatibility.dispatch(events: events, from: identifier)
    case .remapping(let profile):
      guard route.eligibility == .eligible else { return }
      let permit = try requireOperationalPermit(proposedPermit)
      do {
        try await engine.process(
          events: events,
          from: identifier,
          using: profile,
          at: uptimeNanoseconds,
          requiring: permit
        )
      } catch let error as RemappingEventEngineError {
        if error == .outputSuspended {
          if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
          return
        }
        recordEngineFailure(error)
        throw RemappingOutputRoutingError.engine(error)
      }
    case .unavailable(let error): throw error
    }
  }

  /// Retains exact controller identity while a transaction rejects its event output.
  ///
  /// This operation never selects a route or reaches either output sink. Accepted and rolled-back
  /// transactions use the retained identity when installing their completed route set.
  func recordConnectedIdentifierWhileOutputClosed(_ identifier: DeviceIdentifier) throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    connectedIdentifiers.insert(identifier)
    recordUnreconciledRouteIfNeeded(for: identifier)
  }

  func refresh(_ identifier: DeviceIdentifier, requiring permit: RemappingEmissionPermit?)
    async throws
  {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    connectedIdentifiers.insert(identifier)
    guard !profileTransactionState.blocksOutput else {
      recordUnreconciledRouteIfNeeded(for: identifier)
      return
    }
    try await loadSelection(for: identifier, requiring: permit)
  }

  func refreshModel(vendorID: UInt16, productID: UInt16, requiring permit: RemappingEmissionPermit?)
    async throws
  {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    if case .unreconciled(_, let error) = profileTransactionState { throw error }
    let affected = sortedIdentifiers.filter { $0.vendorID == vendorID && $0.productID == productID }
    let profile: RemappingProfile?
    do {
      let frontmostBundleID = foregroundApplication.frontmostBundleIdentifier()
      profile = try await library.activeProfile(
        vendorID: vendorID,
        productID: productID,
        frontmostBundleIdentifier: frontmostBundleID
      )
    } catch let error as RemappingProfileLibraryError {
      try await markLibraryUnavailable(error, identifiers: affected, requiring: permit)
      throw RemappingOutputRoutingError.library(error)
    }
    for identifier in affected {
      _ = try requireOperationalPermit(permit)
      try await transition(
        to: profile.map(RemappingSelectedRoute.remapping) ?? .compatibility,
        for: identifier,
        requiring: permit
      )
    }
  }

  func refreshEligibility(requiring permit: RemappingEmissionPermit?) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    let environment = sampleEligibilityEnvironment()
    if case .unreconciled(_, let error) = profileTransactionState {
      markRoutesUnreconciled(error, environment: environment)
      return
    }
    for identifier in sortedIdentifiers {
      try await reconcileEligibility(for: identifier, environment: environment, requiring: permit)
    }
  }

  func tick(at uptimeNanoseconds: UInt64, requiring proposedPermit: RemappingEmissionPermit?)
    async throws
  {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    guard !profileTransactionState.blocksOutput else { return }
    try await refreshEligibility(requiring: proposedPermit)
    await operationCheckpoint(.tick)
    let hasEligibleRemapping = routes.values.contains {
      if case .remapping = $0.selection { return $0.eligibility == .eligible }
      return false
    }
    guard hasEligibleRemapping else { return }
    let permit = try requireOperationalPermit(proposedPermit)
    do { try await engine.tick(at: uptimeNanoseconds, requiring: permit) } catch let error
      as RemappingEventEngineError
    {
      if error == .outputSuspended {
        if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
        return
      }
      recordEngineFailure(error)
      throw RemappingOutputRoutingError.engine(error)
    }
  }

  func schedulingSnapshot(after uptimeNanoseconds: UInt64, continuousIntervalNanoseconds: UInt64)
    async -> RemappingSchedulingSnapshot
  {
    guard !profileTransactionState.blocksOutput else {
      return RemappingSchedulingSnapshot(
        revision: schedulingRevision,
        nextTickUptimeNanoseconds: nil
      )
    }
    let nextTick = await engine.nextScheduledTick(
      after: uptimeNanoseconds,
      continuousIntervalNanoseconds: continuousIntervalNanoseconds
    )
    return RemappingSchedulingSnapshot(
      revision: schedulingRevision,
      nextTickUptimeNanoseconds: nextTick
    )
  }

  func stopController(
    _ identifier: DeviceIdentifier,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    guard let route = routes[identifier] else { return }
    if profileTransactionState.blocksOutput {
      routes.removeValue(forKey: identifier)
      connectedIdentifiers.remove(identifier)
      return
    }
    switch route.selection {
    case .compatibility: await notifyCompatibilityStop(identifier)
    case .remapping, .unavailable:
      try await releaseAllSafely(for: identifier, requiring: proposedPermit)
    }
    routes.removeValue(forKey: identifier)
    connectedIdentifiers.remove(identifier)
  }

  func shutdown() async throws {
    defer { schedulingRevision &+= 1 }
    terminationRequested = true
    guard !terminalCleanupComplete else { return }
    do { try await engine.drainAfterTermination() } catch let error as RemappingEventEngineError {
      recordEngineFailure(error)
      throw RemappingOutputRoutingError.engine(error)
    }
    for identifier in sortedIdentifiers {
      guard case .compatibility = routes[identifier]?.selection else { continue }
      await notifyCompatibilityStop(identifier)
    }
    routes.removeAll()
    connectedIdentifiers.removeAll()
    terminalCleanupComplete = true
  }

  func loadSelection(for identifier: DeviceIdentifier, requiring permit: RemappingEmissionPermit?)
    async throws
  {
    do {
      let frontmostBundleID = foregroundApplication.frontmostBundleIdentifier()
      let profile = try await library.activeProfile(
        vendorID: identifier.vendorID,
        productID: identifier.productID,
        frontmostBundleIdentifier: frontmostBundleID
      )
      _ = try requireOperationalPermit(permit)
      try await transition(
        to: profile.map(RemappingSelectedRoute.remapping) ?? .compatibility,
        for: identifier,
        requiring: permit
      )
    } catch let error as RemappingProfileLibraryError {
      try await markLibraryUnavailable(error, identifiers: [identifier], requiring: permit)
      throw RemappingOutputRoutingError.library(error)
    }
  }

  private func transition(
    to selection: RemappingSelectedRoute,
    for identifier: DeviceIdentifier,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    _ = try requireOperationalPermit(proposedPermit)
    let oldRoute = routes[identifier]
    if case .compatibility = oldRoute?.selection, case .compatibility = selection {
      let route = compatibilityRoute()
      _ = try requireOperationalPermit(proposedPermit)
      routes[identifier] = route
      return
    }

    if case .remapping(let oldProfile) = oldRoute?.selection,
      case .remapping(let newProfile) = selection, oldProfile == newProfile
    {
      try await reconcileEligibility(for: identifier, requiring: proposedPermit)
      return
    }

    if !profileTransactionState.blocksOutput, case .remapping = oldRoute?.selection {
      try await releaseAllSafely(for: identifier, requiring: proposedPermit)
    }
    if profileTransactionState.blocksOutput {
      // The transaction entry already stopped compatibility output once.
    } else if case .compatibility = oldRoute?.selection, case .compatibility = selection {
    } else if case .compatibility = oldRoute?.selection {
      await notifyCompatibilityStop(identifier)
    }

    switch selection {
    case .compatibility:
      let route = compatibilityRoute()
      _ = try requireOperationalPermit(proposedPermit)
      routes[identifier] = route
    case .remapping(let profile):
      let route = RemappingControllerRoute(
        selection: .remapping(profile),
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: .unavailable,
          environment: sampleEligibilityEnvironment()
        ),
        error: nil
      )
      _ = try requireOperationalPermit(proposedPermit)
      routes[identifier] = route
      try await reconcileEligibility(for: identifier, requiring: proposedPermit)
    case .unavailable(let error):
      _ = try requireOperationalPermit(proposedPermit)
      routes[identifier] = RemappingControllerRoute(
        selection: selection,
        eligibilitySnapshot: RemappingEligibilitySnapshot(
          eligibility: .unavailable,
          environment: sampleEligibilityEnvironment()
        ),
        error: error
      )
    }
  }

  func reconcileEligibility(
    for identifier: DeviceIdentifier,
    environment proposedEnvironment: RemappingEligibilityEnvironment? = nil,
    requiring proposedPermit: RemappingEmissionPermit?,
    forceOutputState: Bool = false
  ) async throws {
    guard var route = routes[identifier] else { return }
    let environment = proposedEnvironment ?? sampleEligibilityEnvironment()
    let applyOutputState = forceOutputState || !profileTransactionState.blocksOutput
    if applyOutputState { _ = try requireOperationalPermit(proposedPermit) }
    switch route.selection {
    case .compatibility:
      let eligibility: RemappingRouteEligibility =
        controls.outputSuppressed || !controls.compatibilityOutputAllowed
        ? .compatibilityOutputSuppressed : .eligible
      route.eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: eligibility,
        environment: environment
      )
      route.error = nil
      routes[identifier] = route
    case .remapping(let profile):
      let eligibility = RemappingForegroundPolicy.eligibility(
        for: profile.applicationScope,
        frontmostBundleIdentifier: environment.frontmostBundleIdentifier,
        accessState: environment.postEventAccessState,
        outputSuppressed: controls.outputSuppressed
      )
      do {
        if eligibility == .eligible && applyOutputState {
          let permit = try requireOperationalPermit(proposedPermit)
          try await recoverEngineIfNeeded(for: route, requiring: permit)
          try await engine.setProfile(profile, for: identifier, requiring: permit)
        } else if applyOutputState {
          let permit = try requireOperationalPermit(proposedPermit)
          try await engine.releaseAll(for: identifier, requiring: permit)
        }
        _ = try requireOperationalPermit(proposedPermit)
        route.eligibilitySnapshot = RemappingEligibilitySnapshot(
          eligibility: eligibility,
          environment: environment
        )
        route.error = nil
        routes[identifier] = route
      } catch let error as RemappingEventEngineError {
        if error == .outputSuspended {
          if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
          return
        }
        recordEngineFailure(error)
        throw RemappingOutputRoutingError.engine(error)
      }
    case .unavailable:
      route.eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: .unavailable,
        environment: environment
      )
      routes[identifier] = route
    }
  }

  private func recoverEngineIfNeeded(
    for route: RemappingControllerRoute,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    guard case .engine = route.error else { return }
    try await engine.recover(requiring: permit)
  }

  private func markLibraryUnavailable(
    _ libraryError: RemappingProfileLibraryError,
    identifiers: [DeviceIdentifier],
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    for identifier in identifiers {
      do {
        try await transition(
          to: .unavailable(.library(libraryError)),
          for: identifier,
          requiring: permit
        )
      } catch let error as RemappingOutputRoutingError {
        if case .engine(let engineError) = error {
          routes[identifier] = RemappingControllerRoute(
            selection: .unavailable(.libraryAndEngine(libraryError, engineError)),
            eligibilitySnapshot: RemappingEligibilitySnapshot(
              eligibility: .unavailable,
              environment: sampleEligibilityEnvironment()
            ),
            error: .libraryAndEngine(libraryError, engineError)
          )
          throw RemappingOutputRoutingError.libraryAndEngine(libraryError, engineError)
        }
        throw error
      }
    }
  }
}
