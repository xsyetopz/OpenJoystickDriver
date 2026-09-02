import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  func compatibilityRoute() -> RemappingControllerRoute {
    let suppressed = controls.outputSuppressed || !controls.compatibilityOutputAllowed
    return RemappingControllerRoute(
      selection: .compatibility,
      eligibilitySnapshot: RemappingEligibilitySnapshot(
        eligibility: suppressed ? .compatibilityOutputSuppressed : .eligible,
        environment: sampleEligibilityEnvironment()
      ),
      error: nil
    )
  }

  func recordEngineFailure(_ error: RemappingEventEngineError) {
    for identifier in sortedIdentifiers {
      guard var route = routes[identifier], case .remapping = route.selection else { continue }
      route.eligibility = .unavailable
      route.error = .engine(error)
      routes[identifier] = route
    }
  }

  func sampleEligibilityEnvironment() -> RemappingEligibilityEnvironment {
    RemappingEligibilityEnvironment(
      frontmostBundleIdentifier: foregroundApplication.frontmostBundleIdentifier(),
      postEventAccessState: postEventAccess.currentState()
    )
  }

  var sortedIdentifiers: [DeviceIdentifier] {
    connectedIdentifiers.sorted { $0.runtimeIdentifier < $1.runtimeIdentifier }
  }

  var compatibilityIsSuppressed: Bool {
    controls.outputSuppressed || !controls.compatibilityOutputAllowed
  }

  func notifyCompatibilityStop(_ identifier: DeviceIdentifier) async {
    await (compatibility as? any ControllerLifecycleListener)?.controllerDidStop(identifier)
  }

  func ensureRunning() throws {
    guard !terminationRequested else { throw RemappingOutputRoutingError.shutDown }
  }

  @discardableResult func requireOperationalPermit(_ permit: RemappingEmissionPermit?) throws
    -> RemappingEmissionPermit
  {
    if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
    guard let permit, emissionBarrier.permits(permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    return permit
  }

  func releaseAllSafely(
    for identifier: DeviceIdentifier,
    requiring proposedPermit: RemappingEmissionPermit?
  ) async throws {
    let permit = try requireOperationalPermit(proposedPermit)
    do { try await engine.releaseAll(for: identifier, requiring: permit) } catch let error
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
}
