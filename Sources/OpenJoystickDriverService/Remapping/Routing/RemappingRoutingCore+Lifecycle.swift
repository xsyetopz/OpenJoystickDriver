import Foundation
import OpenJoystickDriverKit

extension RemappingRoutingCore {
  /// Returns the virtual gamepad for a nil profile or a Joy-Con pair profile, and the remapping
  /// route for any other profile.
  func independentSelection(for profile: RemappingProfile?) -> RemappingSelectedRoute {
    guard let profile, profile.joyConPair == nil else { return .virtualGamepad }
    return .remapping(profile)
  }

  /// Returns a route to the virtual gamepad with the current eligibility.
  func virtualGamepadRoute() -> RemappingControllerRoute {
    RemappingControllerRoute(
      selection: .virtualGamepad,
      eligibilitySnapshot: RemappingEligibilitySnapshot(
        eligibility: virtualGamepadEligibility,
        environment: sampleEligibilityEnvironment()
      ),
      error: nil
    )
  }

  /// Marks every remapping route unavailable because the engine failed with `error`.
  func recordEngineFailure(_ error: RemappingEventEngineError) {
    for identifier in sortedIdentifiers {
      guard var route = routes[identifier], case .remapping = route.selection else { continue }
      route.eligibility = .unavailable
      route.error = .engine(error)
      routes[identifier] = route
    }
  }

  /// Reads the frontmost application and the post-event access state.
  func sampleEligibilityEnvironment() -> RemappingEligibilityEnvironment {
    RemappingEligibilityEnvironment(
      frontmostAppID: foregroundApplication.frontmostAppID(),
      postEventAccessState: postEventAccess.currentState()
    )
  }

  /// The connected controllers in order.
  var sortedIdentifiers: [LogicalControllerID] {
    connectedIdentifiers.sorted()
  }

  /// The eligibility of a virtual-gamepad route: suppressed when output is suppressed, eligible
  /// otherwise.
  var virtualGamepadEligibility: RemappingRouteEligibility {
    controls.outputSuppressed ? .virtualOutputSuppressed : .eligible
  }

  /// Forgets the engine baselines of sources the route stopped feeding to the engine, so input
  /// that changed meanwhile is diffed against neutral when feeding resumes.
  func endSources(_ sources: some Sequence<LogicalControllerID>) async {
    for source in sources { await engine.endSource(source) }
  }

  /// Tells the virtual gamepad output that `identifier` stopped, if it listens.
  func notifyVirtualGamepadStop(_ identifier: LogicalControllerID) async {
    await (virtualOutput as? any ControllerLifecycleListener)?.controllerDidStop(identifier)
  }

  /// Throws ``RemappingOutputRoutingError/shutDown`` once shutdown was requested.
  func ensureRunning() throws {
    guard !terminationRequested else { throw RemappingOutputRoutingError.shutDown }
  }

  /// Returns `permit` when the emission barrier still permits it.
  ///
  /// - Throws: ``RemappingOutputRoutingError/shutDown`` when the barrier is terminated, and
  ///   ``RemappingEventEngineError/outputSuspended`` when `permit` is nil or not permitted.
  @discardableResult
  func requireOperationalPermit(
    _ permit: RemappingEmissionPermit?
  ) throws -> RemappingEmissionPermit {
    if emissionBarrier.isTerminated { throw RemappingOutputRoutingError.shutDown }
    guard let permit, emissionBarrier.permits(permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    return permit
  }

  /// Releases the output of `identifier` and tells the virtual gamepad that it stopped when
  /// `profile` publishes one.
  ///
  /// - Throws: The failure to release the output, after the virtual gamepad was told.
  func releaseAndRetire(
    for identifier: LogicalControllerID,
    profile: RemappingProfile,
    requiring permit: RemappingEmissionPermit?
  ) async throws {
    var releaseError: (any Error)?
    do { try await releaseAllSafely(for: identifier, requiring: permit) } catch {
      releaseError = error
    }
    if profile.outputPolicy.virtualGamepad != .disabled {
      await notifyVirtualGamepadStop(identifier)
    }
    if let releaseError { throw releaseError }
  }

  /// Releases everything that the engine holds for `identifier`.
  ///
  /// An output suspension ends the release without failing, unless the barrier is terminated.
  ///
  /// - Throws: ``RemappingOutputRoutingError`` for a failure of the engine, and
  ///   ``RemappingOutputRoutingError/shutDown`` once the barrier is terminated.
  func releaseAllSafely(
    for identifier: LogicalControllerID,
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
