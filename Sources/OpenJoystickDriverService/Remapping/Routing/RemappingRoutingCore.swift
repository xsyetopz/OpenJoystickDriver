import CryptoKit
import Foundation
import OpenJoystickDriverKit

/// What one routed call carries: a controller's snapshot, or a request to activate its output.
enum RemappingRoutedInput: Sendable {
  /// A controller input snapshot.
  case input(ControllerEvent)
  /// A request to activate the output of the controller.
  case activation
}

/// The actor that selects the output of each controller and routes its input to the virtual gamepad
/// or the remapping engine.
actor RemappingRoutingCore {
  /// The library that supplies the active remapping profile.
  let library: RemappingProfileLibrary
  /// The engine that turns input into remapped output.
  let engine: RemappingEventEngine
  /// The virtual gamepad output.
  let virtualOutput: any OutputDispatcher
  /// The source of the frontmost application.
  let foregroundApplication: any RemappingForegroundApplicationProviding
  /// The source of the post-event access state.
  let postEventAccess: any RemappingPostEventAccessProviding
  /// Called at the stages of an operation, so a test can pause there.
  let operationCheckpoint: @Sendable (RemappingRoutingCheckpoint) async -> Void
  /// The key under which the port keys of profile units are computed.
  let installationKey: SymmetricKey
  /// The engine's barrier that gates its output.
  var emissionBarrier: RemappingEmissionBarrier { engine.emissionBarrier }
  /// The router-wide output controls.
  var controls = RemappingRoutingControls(outputSuppressed: false, revision: 0)
  /// The route of every controller; changing it publishes the observed input demand.
  var routes: [LogicalControllerID: RemappingControllerRoute] = [:] {
    didSet { publishObservedInputDemand() }
  }
  /// The controllers that have sent input and have not stopped.
  var connectedIdentifiers: Set<LogicalControllerID> = []
  /// The input ownership of each controller.
  var inputOwnership: [LogicalControllerID: HIDInputOwnership] = [:]
  /// The Joy-Con pair sessions, by session ID.
  var joyConPairs: [UUID: RemappingJoyConPairSession] = [:]
  /// The session ID of each paired Joy-Con; changing it publishes the observed input demand.
  var joyConPairByMember: [LogicalControllerID: UUID] = [:] {
    didSet { publishObservedInputDemand() }
  }
  /// Controllers a remapping route or Joy-Con pair consumes, for observe-only pipelines.
  let observedInputDemand = RemappingObservedInputDemand()
  /// Controllers whose active profile binds a pointer axis.
  let pointerInputDemand = RemappingObservedInputDemand()
  /// The state of the profile transaction.
  var profileTransactionState = RemappingProfileTransactionState.inactive
  /// Whether shutdown was requested.
  var terminationRequested = false
  /// Whether the terminal cleanup finished.
  internal var terminalCleanupComplete = false
  /// The number of changes that affect scheduling, which a snapshot reports.
  var schedulingRevision: UInt64 = 0

  /// Creates the core over its library, engine, output and system sources.
  init(
    library: RemappingProfileLibrary,
    engine: RemappingEventEngine,
    virtualOutput: any OutputDispatcher,
    foregroundApplication: any RemappingForegroundApplicationProviding,
    postEventAccess: any RemappingPostEventAccessProviding,
    installationKey: SymmetricKey,
    operationCheckpoint: @escaping @Sendable (RemappingRoutingCheckpoint) async -> Void
  ) {
    self.library = library
    self.engine = engine
    self.virtualOutput = virtualOutput
    self.foregroundApplication = foregroundApplication
    self.postEventAccess = postEventAccess
    self.installationKey = installationKey
    self.operationCheckpoint = operationCheckpoint
  }

  /// Publishes the controllers that a remapping route or a Joy-Con pair consumes, and the ones
  /// whose profile binds a pointer axis.
  private func publishObservedInputDemand() {
    let remapped = routes.compactMap { $0.value.selection.profile == nil ? nil : $0.key }
    observedInputDemand.replace(with: Set(remapped).union(joyConPairByMember.keys))
    pointerInputDemand.replace(
      with: Set(
        routes.compactMap { $0.value.selection.profile?.bindsPointer == true ? $0.key : nil }
      )
    )
  }

  /// Applies `proposed` when it is no older than the current controls, and reconciles the routes.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the router is shut down or a route fails.
  func apply(
    _ proposed: RemappingRoutingControls,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    _ = try requireOperationalPermit(permit)
    guard proposed.revision >= controls.revision else { return }
    let suppressionBegan = !controls.outputSuppressed && proposed.outputSuppressed
    let outputSuppressionChanged = proposed.outputSuppressed != controls.outputSuppressed
    controls = proposed
    await operationCheckpoint(.apply)
    _ = try requireOperationalPermit(permit)
    if case .unreconciled = profileTransactionState { return }
    if suppressionBegan, !profileTransactionState.blocksOutput {
      for identifier in sortedIdentifiers {
        guard case .virtualGamepad = routes[identifier]?.selection else { continue }
        await notifyVirtualGamepadStop(identifier)
      }
    }
    guard outputSuppressionChanged else { return }
    try await refreshEligibility(requiring: permit)
  }

  /// Routes `input` of `identifier` to the output that its route selects.
  ///
  /// The virtual gamepad takes the input when its route is eligible. The remapping engine processes
  /// it with the active profile when that route is eligible. A paired Joy-Con is routed through its
  /// pair. The call drops the input while a profile transaction blocks output.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the route is unavailable, the engine fails or
  ///   the router is shut down.
  func dispatch(
    _ input: RemappingRoutedInput,
    from identifier: LogicalControllerID,
    at uptimeNanoseconds: UInt64,
    requiring proposedPermit: RemappingEmissionPermit?,
    onPublished: @escaping @Sendable () -> Void = {}
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
    let pair = pairSession(for: identifier)
    let routingIdentifier = pair?.left ?? identifier
    try await reconcileEligibility(for: routingIdentifier, requiring: proposedPermit)
    await operationCheckpoint(.dispatch)
    guard let route = routes[routingIdentifier] else { return }
    switch route.selection {
    case .virtualGamepad:
      guard route.eligibility == .eligible else { return }
      _ = try requireOperationalPermit(proposedPermit)
      switch input {
      case .input(let event):
        try? await virtualOutput.consume(
          .controller(event, from: identifier),
          onDelivered: onPublished
        )
      case .activation:
        try? await virtualOutput.consume(.activation(identifier)) {}
      }
    case .remapping(let profile):
      guard route.eligibility == .eligible else { return }
      let permit = try requireOperationalPermit(proposedPermit)
      do {
        switch input {
        case .input(let event):
          try await engine.process(
            pairEvent(event, from: identifier),
            from: identifier,
            into: routingIdentifier,
            using: profile,
            at: uptimeNanoseconds,
            requiring: permit
          )
        case .activation:
          try await engine.setProfile(profile, for: routingIdentifier, requiring: permit)
        }
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
  func recordConnectedIdentifierWhileOutputClosed(_ identifier: LogicalControllerID) throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    connectedIdentifiers.insert(identifier)
    recordUnreconciledRouteIfNeeded(for: identifier)
  }

  /// Selects the output of `identifier` again from the active profile.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the library or engine fails.
  func refresh(
    _ identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    connectedIdentifiers.insert(identifier)
    guard !profileTransactionState.blocksOutput else {
      recordUnreconciledRouteIfNeeded(for: identifier)
      return
    }
    try await loadSelection(for: identifier, requiring: permit)
  }

  /// Selects the output again for every connected controller of the model `vendorID` and
  /// `productID`.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the library or engine fails.
  func refreshModel(
    vendorID: UInt16,
    productID: UInt16,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    try ensureRunning()
    if case .unreconciled(_, let error) = profileTransactionState { throw error }
    let affected = sortedIdentifiers.filter {
      $0.model.vendorID == vendorID && $0.model.productID == productID
    }
    var profiles: [RemappingProfile?] = []
    do {
      let frontmostBundleID = foregroundApplication.frontmostAppID()
      for identifier in affected {
        profiles.append(
          try await library.activeProfile(
            vendorID: vendorID,
            productID: productID,
            unit: ControllerPortKey.of(identifier, installationKey: installationKey)?.rawValue,
            frontmostAppID: frontmostBundleID
          )
        )
      }
    } catch let error as RemappingProfileLibraryError {
      try await markLibraryUnavailable(error, identifiers: affected, requiring: permit)
      throw RemappingOutputRoutingError.library(error)
    }
    for (identifier, profile) in zip(affected, profiles) {
      _ = try requireOperationalPermit(permit)
      try await transition(
        to: independentSelection(for: profile),
        for: identifier,
        requiring: permit
      )
    }
  }

  /// Recomputes the eligibility of every route.
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

  /// Advances the remapping engine to `uptimeNanoseconds` when a remapping route is eligible.
  func tick(
    at uptimeNanoseconds: UInt64,
    requiring proposedPermit: RemappingEmissionPermit?,
    onPublished _: @Sendable () -> Void = {}
  ) async throws {
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

  /// Returns the revision and the uptime of the next tick after `uptimeNanoseconds`, or no tick
  /// while a profile transaction blocks output.
  func schedulingSnapshot(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) async -> RemappingSchedulingSnapshot {
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

  /// Releases the output of `identifier` and removes its route.
  func stopController(
    _ identifier: LogicalControllerID,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    defer { schedulingRevision &+= 1 }
    inputOwnership.removeValue(forKey: identifier)
    await engine.endSource(identifier)
    if try await stopPairedJoyCon(identifier, requiring: proposedPermit) { return }
    guard let route = routes[identifier] else { return }
    if profileTransactionState.blocksOutput {
      routes.removeValue(forKey: identifier)
      connectedIdentifiers.remove(identifier)
      return
    }
    switch route.selection {
    case .virtualGamepad: await notifyVirtualGamepadStop(identifier)
    case .remapping(let profile):
      try await releaseAndRetire(for: identifier, profile: profile, requiring: proposedPermit)
    case .unavailable: try await releaseAllSafely(for: identifier, requiring: proposedPermit)
    }
    routes.removeValue(forKey: identifier)
    connectedIdentifiers.remove(identifier)
  }

  /// The controllers whose routes shutdown retired.
  internal var terminalRetiredIdentifiers = Set<LogicalControllerID>()

  /// Stops the router: drains the engine, tells the virtual gamepad that each retired route
  /// stopped, clears the routes and rejects later calls.
  func shutdown() async throws {
    defer { schedulingRevision &+= 1 }
    terminationRequested = true
    guard !terminalCleanupComplete else { return }
    var cleanupError: (any Error)?
    do { try await engine.drainAfterTermination() } catch let error as RemappingEventEngineError {
      recordEngineFailure(error)
      cleanupError = RemappingOutputRoutingError.engine(error)
    } catch { cleanupError = error }
    for identifier in sortedIdentifiers where !terminalRetiredIdentifiers.contains(identifier) {
      if let session = pairSession(for: identifier), identifier != session.left { continue }
      switch routes[identifier]?.selection {
      case .virtualGamepad: await notifyVirtualGamepadStop(identifier)
      case .remapping(let profile) where profile.outputPolicy.virtualGamepad != .disabled:
        await notifyVirtualGamepadStop(identifier)
      default: continue
      }
      terminalRetiredIdentifiers.insert(identifier)
    }
    if let cleanupError { throw cleanupError }
    routes.removeAll()
    connectedIdentifiers.removeAll()
    inputOwnership.removeAll()
    joyConPairs.removeAll()
    joyConPairByMember.removeAll()
    terminalCleanupComplete = true
  }

}
