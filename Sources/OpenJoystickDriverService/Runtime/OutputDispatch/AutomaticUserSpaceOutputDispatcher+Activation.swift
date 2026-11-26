import Foundation
import OpenJoystickDriverKit

extension AutomaticUserSpaceOutputDispatcher {
  /// Starts the session of `identifier` and publishes its selected profile.
  ///
  /// - Throws: `CancellationError` when the dispatcher is closed, or the failure of the build.
  func activate(controller identifier: LogicalControllerID) async throws {
    let generation = ledger.cacheGeneration(for: identifier)
    let description = await resolver.description(for: identifier)
    try await coordinator.activateOne(
      identifier: identifier,
      descriptions: description.map { [identifier: $0] } ?? [:],
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] identifier, description in
        guard let self else { return nil }
        return resolver.profile(
          for: identifier,
          description: description,
          generation: generation,
          notifying: self
        )
      },
      factory: resolver.factory(for: identifier)
    )
    await synchronizeDiagnostics()
  }

  /// Publishes the selected profile of each of `identifiers`.
  ///
  /// - Throws: ``UserSpaceOutputDispatcher/CreationError/createFailed`` when the dispatcher is
  ///   closed or already holds controllers, and the failure of the first controller that fails.
  func activate(for identifiers: [LogicalControllerID]) async throws {
    let generations = ledger.cacheGenerations(for: identifiers)
    try await coordinator.activate(
      identifiers: identifiers,
      descriptions: await resolver.descriptions(),
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] identifier, description in
        guard let self, let generation = generations[identifier] else { return nil }
        return resolver.profile(
          for: identifier,
          description: description,
          generation: generation,
          notifying: self
        )
      },
      factory: { [resolver] in resolver.factory(for: $0) }
    )
    await synchronizeDiagnostics()
  }

  /// Whether `identifier` has an active session and the serving policy publishes `profile` for it.
  func isEligible(
    _ identifier: LogicalControllerID,
    profile: VirtualHIDProfileID
  ) async -> Bool {
    await resolver.isEligible(identifier, profile: profile)
  }

  /// Reselects the profile for one controller and, when the profile changes, replaces only that
  /// controller's backend.
  ///
  /// The selection is recorded only once the replacement succeeds.
  ///
  /// The replacement is built and activated while the live backend keeps publishing, and the
  /// live backend is neutralized before it is retired; when the replacement cannot be built or
  /// activated, the live backend and its selection stay and the error is rethrown. The cost of
  /// that order: for a moment both virtual devices exist with the same serial number and
  /// LocationID, and consumers may see a second pad. A controller with no live backend (during
  /// pausing, recovery, or before activation) publishes the selection when it next installs.
  func retarget(controller identifier: LogicalControllerID) async throws {
    let generation = ledger.cacheGeneration(for: identifier)
    guard let description = await resolver.cachedDescription(for: identifier),
      let selection = resolver.select(for: description)
    else { return }
    let (current, liveIdentity) = ledger.selectionAndIdentity(for: identifier)
    let currentIdentity = resolver.identity(for: description)
    let identityChanged = currentIdentity != liveIdentity
    guard current != selection || identityChanged else { return }
    var identity = liveIdentity
    if current?.profileID != selection.profileID || identityChanged {
      // The replacement is built with the current persona identity. The identity is fixed
      // when a device is created, so an identity change alone rebuilds the same profile.
      identity = currentIdentity
      ledger.setIdentity(identity, for: identifier)
      do {
        try await coordinator.retarget(
          identifier,
          target: selection.profileID,
          rebuildsLiveTarget: identityChanged,
          isEligible: { [weak self] identifier, profile in
            await self?.isEligible(identifier, profile: profile) ?? false
          },
          factory: resolver.factory(for: identifier)
        )
      } catch {
        ledger.setIdentity(liveIdentity, for: identifier)
        await synchronizeDiagnostics()
        throw error
      }
    }
    resolver.commit(
      selection,
      identity: identity,
      for: identifier,
      generation: generation,
      notifying: self
    )
    await synchronizeDiagnostics()
  }
}
