import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  func status(for identifier: DeviceIdentifier) -> RemappingRouteStatus? {
    guard let route = routes[identifier] else { return nil }
    return makeStatus(identifier: identifier, route: route)
  }

  func statuses() -> [RemappingRouteStatus] {
    sortedIdentifiers.compactMap { identifier in
      routes[identifier].map { makeStatus(identifier: identifier, route: $0) }
    }
  }

  func statusSnapshot(
    applying proposedControls: RemappingRoutingControls,
    requiring permit: RemappingEmissionPermit?
  ) async -> RemappingRouterStatusSnapshot {
    defer { schedulingRevision &+= 1 }
    if proposedControls.revision >= controls.revision {
      let previousCompatibilitySuppressed = compatibilityIsSuppressed
      controls = proposedControls
      if !previousCompatibilitySuppressed, compatibilityIsSuppressed,
        !profileTransactionState.blocksOutput
      {
        for identifier in sortedIdentifiers {
          guard case .compatibility = routes[identifier]?.selection else { continue }
          notifyCompatibilityStop(identifier)
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
      postEventAccessState: environment.postEventAccessState
    )
  }

  private func refreshEligibility(
    environment: RemappingEligibilityEnvironment,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    for identifier in sortedIdentifiers {
      try await reconcileEligibility(for: identifier, environment: environment, requiring: permit)
    }
  }

  private func makeStatus(identifier: DeviceIdentifier, route: RemappingControllerRoute)
    -> RemappingRouteStatus
  {
    let selection: RemappingRouteSelection
    let profile: RemappingProfile?
    switch route.selection {
    case .compatibility:
      selection = .compatibility
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
      frontmostBundleIdentifier: route.eligibilitySnapshot.frontmostBundleIdentifier,
      postEventAccessState: route.eligibilitySnapshot.postEventAccessState,
      error: route.error
    )
  }

}
