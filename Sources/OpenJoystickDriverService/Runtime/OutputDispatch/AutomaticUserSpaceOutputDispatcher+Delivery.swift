import Foundation
import OpenJoystickDriverKit

extension AutomaticUserSpaceOutputDispatcher {
  /// Publishes `event` from `identifier` and ignores a failure.
  func dispatch(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID
  ) async {
    let unobserved: @Sendable () -> Void = {}
    try? await dispatchPublishing(
      event,
      from: identifier,
      onPublished: unobserved
    )
  }

  /// Publishes `event` from `identifier`; `onPublished` runs once the backend has published it.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no backend can publish, or the
  ///   failure of the backend, which also starts recovery of the publication.
  func dispatchPublishing(
    _ event: ControllerEvent,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void
  ) async throws {
    do {
      try await deliver(.input(event), from: identifier, onPublished: onPublished)
    } catch {
      await synchronizeDiagnostics()
      throw error
    }
  }

  /// Activation marks the start of a controller session, so it also begins a physical
  /// session for a controller whose earlier session stopped.
  func activateOutput(for identifier: LogicalControllerID) async {
    await coordinator.beginSession(identifier)
    try? await deliver(.activation, from: identifier)
    await synchronizeDiagnostics()
  }

  /// Sends the remapped gamepad `state` of `identifier`.
  ///
  /// An at-rest state goes only to an existing backend and never creates one. Any other state
  /// activates the controller first unless it already publishes.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no backend can take the state, or
  ///   the failure of the backend, which also starts recovery of the publication.
  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws {
    guard state == .neutral else {
      // A remapped stream sends a state per input report; activation reads the controller from
      // the device manager, which only a controller with no backend needs.
      if await coordinator.installedBackend(for: identifier) == nil {
        try await activate(controller: identifier)
      }
      try await deliver(.remapped(state), from: identifier)
      return
    }
    guard let lease = await coordinator.leaseForNeutralization(identifier) else { return }
    do {
      recordSendAttempt(for: identifier)
      guard let sink = lease.backend as? any RemappingGamepadSink else {
        throw RemappingEventEngineError.sinkUnavailable
      }
      try await sink.send(state, for: identifier)
      recordSendCompletion(for: identifier)
      await coordinator.recordPublicationCompletion(for: identifier)
    } catch {
      await lease.release()
      await coordinator.recoverPublication(for: identifier, failure: error)
      await synchronizeDiagnostics()
      throw error
    }
    await lease.release()
    await synchronizeDiagnostics()
  }

  /// Publishes `delivery` through the leased backend of `identifier` and records the attempt.
  ///
  /// A failed publication starts recovery.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no backend can publish, or the
  ///   failure of the backend.
  func deliver(
    _ delivery: AutomaticOutputDelivery,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void = {}
  ) async throws {
    // `suppressOutput` can be set without `setOutputSuppressed`, so a delivery applies a value
    // the coordinator has not seen.
    if ledger.suppressionNeedsApplying {
      await synchronizeSuppression()
    }
    let generation = ledger.cacheGeneration(for: identifier)
    guard let description = await resolver.cachedDescription(for: identifier),
      let profile = resolver.profile(
        for: identifier,
        description: description,
        generation: generation,
        notifying: self
      ),
      let grant = await coordinator.grantForDelivery(
        controller: identifier,
        profile: profile,
        isEligible: { [weak self] identifier, profile in
          await self?.isEligible(identifier, profile: profile) ?? false
        },
        factory: resolver.factory(for: identifier)
      )
    else { throw RemappingEventEngineError.sinkUnavailable }
    let lease = grant.lease
    do {
      recordSendAttempt(for: identifier)
      try await delivery.publish(
        through: lease.backend,
        for: identifier,
        onPublished: onPublished
      )
      recordSendCompletion(for: identifier)
      if grant.clearsFailure { await coordinator.recordPublicationCompletion(for: identifier) }
    } catch {
      await lease.release()
      await coordinator.recoverPublication(for: identifier, failure: error)
      await synchronizeDiagnostics()
      throw error
    }
    await lease.release()
    // A cleared failure changed the coordinator after the grant read its revision.
    await synchronizeDiagnostics(
      knownRevision: grant.clearsFailure ? nil : grant.revision,
      timingsMoved: true
    )
  }

  /// Records that a send to the virtual gamepad of `identifier` was attempted.
  private func recordSendAttempt(for identifier: LogicalControllerID) {
    ledger.recordSendAttempt(for: identifier, at: DispatchTime.now().uptimeNanoseconds)
  }

  /// Records that a send to the virtual gamepad of `identifier` completed.
  private func recordSendCompletion(for identifier: LogicalControllerID) {
    ledger.recordSendCompletion(for: identifier, at: DispatchTime.now().uptimeNanoseconds)
  }

  /// Copies the coordinator state into the status and posts a change when it differs.
  ///
  /// A delivery passes the coordinator `knownRevision` its grant read: while it equals the
  /// revision of the last snapshot, nothing the snapshot holds can have changed, so the snapshot is
  /// read again only once per announcement interval, which also picks up a change inside a
  /// backend's own status. A change to the send timings alone (`timingsMoved`) is posted at most
  /// once per interval: each input report moves them, and every post makes the app read the whole
  /// status again.
  func synchronizeDiagnostics(
    knownRevision: UInt64? = nil,
    timingsMoved: Bool = false
  ) async {
    let now = DispatchTime.now().uptimeNanoseconds
    let (current, intervalElapsed) = ledger.diagnosticsGate(knownRevision: knownRevision, now: now)
    var changed = false
    if !current || intervalElapsed {
      let (snapshot, revision) = await coordinator.publicationSnapshot()
      changed = ledger.replacePublication(snapshot, revision: revision)
    }
    let announce = ledger.claimAnnouncement(
      shouldAnnounce: changed || (timingsMoved && intervalElapsed),
      now: now
    )
    if announce { NotificationCenter.postServiceStatusChanged(from: self) }
  }
}
