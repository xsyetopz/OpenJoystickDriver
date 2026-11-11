import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  /// Selects the route of `identifier` from its active profile and transitions to it.
  ///
  /// A Joy-Con pair member reconciles its pair session instead.
  ///
  /// - Throws: ``RemappingOutputRoutingError/library(_:)`` when the profile library fails, and the
  ///   errors of ``transition(to:for:requiring:)``.
  func loadSelection(
    for identifier: LogicalControllerID,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    if let session = pairSession(for: identifier) {
      try await reconcileJoyConPair(
        session,
        environment: sampleEligibilityEnvironment(),
        requiring: permit
      )
      return
    }
    do {
      let frontmostBundleID = foregroundApplication.frontmostAppID()
      let profile = try await library.activeProfile(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        unit: ControllerPortKey.of(identifier, installationKey: installationKey)?.rawValue,
        frontmostAppID: frontmostBundleID
      )
      _ = try requireOperationalPermit(permit)
      try await transition(
        to: independentSelection(for: profile),
        for: identifier,
        requiring: permit
      )
    } catch let error as RemappingProfileLibraryError {
      try await markLibraryUnavailable(error, identifiers: [identifier], requiring: permit)
      throw RemappingOutputRoutingError.library(error)
    }
  }

  /// Moves the route of `identifier` to `selection`, releasing the output of the route it leaves.
  ///
  /// A virtual gamepad to virtual gamepad change only refreshes the route, and an unchanged profile
  /// only reconciles eligibility.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` when the permit is not valid or the engine
  ///   fails.
  internal func transition(
    to selection: RemappingSelectedRoute,
    for identifier: LogicalControllerID,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    _ = try requireOperationalPermit(proposedPermit)
    let oldRoute = routes[identifier]
    if case .virtualGamepad = oldRoute?.selection, case .virtualGamepad = selection {
      let route = virtualGamepadRoute()
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

    if !profileTransactionState.blocksOutput, case .remapping(let profile) = oldRoute?.selection {
      try await releaseAndRetire(for: identifier, profile: profile, requiring: proposedPermit)
    }
    if profileTransactionState.blocksOutput {
      // The transaction entry already stopped the virtual gamepad output once.
    } else if case .virtualGamepad = oldRoute?.selection, case .virtualGamepad = selection {
    } else if case .virtualGamepad = oldRoute?.selection {
      await notifyVirtualGamepadStop(identifier)
    }
    // A profile switch keeps feeding the engine; any other route stops, so its baseline goes.
    if selection.profile == nil { await engine.endSource(identifier) }

    switch selection {
    case .virtualGamepad:
      let permit = try requireOperationalPermit(proposedPermit)
      try await engine.setProfileColor(nil, for: identifier, requiring: permit)
      let route = virtualGamepadRoute()
      _ = try requireOperationalPermit(proposedPermit)
      routes[identifier] = route
    case .remapping(let profile):
      let permit = try requireOperationalPermit(proposedPermit)
      try await engine.setProfileColor(profile.physicalColor, for: identifier, requiring: permit)
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
      let permit = try requireOperationalPermit(proposedPermit)
      try await engine.setProfileColor(nil, for: identifier, requiring: permit)
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

  /// Records the input ownership of `identifier` and reconciles its eligibility.
  func updateInputOwnership(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async throws {
    guard !terminationRequested else { return }
    inputOwnership[identifier] = ownership
    schedulingRevision &+= 1
    await (virtualOutput as? any ControllerInputOwnershipListener)?
      .controllerInputOwnershipChanged(ownership, for: identifier)
    guard !profileTransactionState.blocksOutput, let permit = emissionBarrier.currentPermit() else {
      return
    }
    try await reconcileEligibility(for: identifier, requiring: permit)
  }

  /// Returns the eligibility of `profile` for `identifier` in `environment`.
  ///
  /// A profile that requires exclusive input is not eligible while the controller input is shared.
  func remappingEligibility(
    _ profile: RemappingProfile,
    for identifier: LogicalControllerID,
    environment: RemappingEligibilityEnvironment
  ) -> RemappingRouteEligibility {
    let eligibility = RemappingForegroundPolicy.eligibility(
      for: profile.applicationScope,
      frontmostAppID: environment.frontmostAppID,
      accessState: environment.postEventAccessState,
      outputSuppressed: controls.outputSuppressed,
      requiresPostEventAccess: profile.requiresSystemInputAccess
    )
    guard eligibility == .eligible else { return eligibility }
    if profile.outputPolicy.requiresExclusiveInput, inputOwnership[identifier] != .exclusive {
      return .physicalInputNotExclusive
    }
    return .eligible
  }

  /// Brings the route of `identifier` in line with its eligibility, starting or releasing the
  /// engine.
  ///
  /// - Parameters:
  ///   - identifier: The controller to reconcile.
  ///   - proposedEnvironment: The environment to judge by; sampled when nil.
  ///   - proposedPermit: The emission permit that the engine calls require.
  ///   - forceOutputState: Applies the engine change even while a profile transaction blocks
  ///     output.
  /// - Throws: ``RemappingOutputRoutingError/shutDown`` once shutdown was requested, and
  ///   ``RemappingOutputRoutingError/engine(_:)`` when the engine fails.
  func reconcileEligibility(
    for identifier: LogicalControllerID,
    environment proposedEnvironment: RemappingEligibilityEnvironment? = nil,
    requiring proposedPermit: RemappingEmissionPermit?,
    forceOutputState: Bool = false
  ) async throws {
    if let session = pairSession(for: identifier) {
      try await reconcileJoyConPair(
        session,
        environment: proposedEnvironment ?? sampleEligibilityEnvironment(),
        requiring: proposedPermit
      )
      return
    }
    guard var route = routes[identifier] else { return }
    let environment = proposedEnvironment ?? sampleEligibilityEnvironment()
    let applyOutputState = forceOutputState || !profileTransactionState.blocksOutput
    if applyOutputState { _ = try requireOperationalPermit(proposedPermit) }
    switch route.selection {
    case .virtualGamepad:
      route.eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: virtualGamepadEligibility,
        environment: environment
      )
      route.error = nil
      routes[identifier] = route
    case .remapping(let profile):
      let eligibility = remappingEligibility(profile, for: identifier, environment: environment)
      if eligibility != .eligible, route.eligibility == .eligible {
        await engine.endSource(identifier)
      }
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
        guard routes[identifier]?.selection == route.selection else { return }
        if remappingEligibility(profile, for: identifier, environment: environment) != eligibility {
          try await reconcileEligibility(
            for: identifier,
            environment: environment,
            requiring: proposedPermit,
            forceOutputState: forceOutputState
          )
          return
        }
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

  /// Recovers the engine when the error of `route` is an engine failure.
  internal func recoverEngineIfNeeded(
    for route: RemappingControllerRoute,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    guard case .engine = route.error else { return }
    try await engine.recover(requiring: permit)
  }

  /// Moves each of `identifiers` to an unavailable route that carries `libraryError`.
  ///
  /// - Throws: ``RemappingOutputRoutingError/libraryAndEngine(_:_:)`` when an engine failure
  ///   occurs as well.
  internal func markLibraryUnavailable(
    _ libraryError: RemappingProfileLibraryError,
    identifiers: [LogicalControllerID],
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
