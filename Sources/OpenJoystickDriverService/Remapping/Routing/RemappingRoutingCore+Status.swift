import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  /// Returns the status of the route of `identifier`, or nil when it has no route.
  func status(for identifier: LogicalControllerID) -> RemappingRouteStatus? {
    guard let route = routes[identifier] else { return nil }
    return makeStatus(identifier: identifier, route: route)
  }

  /// Returns the status of every route, in controller order.
  func statuses() -> [RemappingRouteStatus] {
    sortedIdentifiers.compactMap { identifier in
      routes[identifier].map { makeStatus(identifier: identifier, route: $0) }
    }
  }

  /// Applies `proposedControls` when they are no older than the current ones, refreshes the
  /// eligibility of every route and returns the routes and pairs.
  ///
  /// A failure of the refresh stays in the route statuses; this function does not throw.
  func statusSnapshot(
    applying proposedControls: RemappingRoutingControls,
    requiring permit: RemappingEmissionPermit?
  ) async -> RemappingRouterStatusSnapshot {
    defer { schedulingRevision &+= 1 }
    if proposedControls.revision >= controls.revision {
      let suppressionBegan = !controls.outputSuppressed && proposedControls.outputSuppressed
      controls = proposedControls
      if suppressionBegan, !profileTransactionState.blocksOutput {
        for identifier in sortedIdentifiers {
          guard case .virtualGamepad = routes[identifier]?.selection else { continue }
          await notifyVirtualGamepadStop(identifier)
        }
      }
    }
    let environment = sampleEligibilityEnvironment()
    if case .unreconciled(_, let error) = profileTransactionState {
      markRoutesUnreconciled(error, environment: environment)
    } else {
      do { try await refreshEligibility(environment: environment, requiring: permit) } catch {
        // The route statuses retain the typed engine/library failure recorded by
        // reconciliation. Status sampling itself remains nonthrowing for RPC use.
      }
    }
    return RemappingRouterStatusSnapshot(
      routes: statuses(),
      joyConPairs: sortedJoyConPairs(),
      postEventAccessState: environment.postEventAccessState
    )
  }

  /// Reconciles the eligibility of every route in `environment`.
  private func refreshEligibility(
    environment: RemappingEligibilityEnvironment,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    for identifier in sortedIdentifiers {
      try await reconcileEligibility(for: identifier, environment: environment, requiring: permit)
    }
  }

  /// Builds the status of `route`.
  private func makeStatus(
    identifier: LogicalControllerID,
    route: RemappingControllerRoute
  ) -> RemappingRouteStatus {
    let selection: RemappingRouteSelection
    let profile: RemappingProfile?
    switch route.selection {
    case .virtualGamepad:
      selection = .virtualGamepad
      profile = nil
    case .remapping(let activeProfile):
      selection = .remapping(profileID: activeProfile.id)
      profile = activeProfile
    case .unavailable:
      selection = .unavailable
      profile = nil
    }
    return RemappingRouteStatus(
      identifier: identifier,
      selection: selection,
      eligibility: route.eligibility,
      activeProfileID: profile?.id,
      activeProfileName: profile?.name,
      applicationScope: profile?.applicationScope,
      frontmostAppID: route.eligibilitySnapshot.frontmostAppID,
      postEventAccessState: route.eligibilitySnapshot.postEventAccessState,
      error: route.error
    )
  }

}
