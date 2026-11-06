import Foundation
import OpenJoystickDriverKit

/// Publishes a user-space virtual gamepad per controller, choosing and replacing the profile of
/// each backend as the controller, its ownership and the personas change.
///
/// Each controller's backend is built on demand by the coordinator, so a controller with no profile
/// that can represent it publishes nothing and is reported through ``status``.
/// - Note: `@unchecked Sendable` because `stateLock` guards every mutable property.
final class AutomaticUserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, ControllerLifecycleListener, ControllerInputOwnershipListener,
  RemappingGamepadSink, RemappingGamepadOutputControlling, @unchecked Sendable
{
  /// Supplies the connected controllers and their sessions.
  private let deviceManager: DeviceManager
  /// Reports who holds the input of a controller.
  private let ownershipProvider:
    @Sendable (LogicalControllerID) async -> ControllerOwnershipObservation
  /// Describes every connected controller.
  private let descriptionsProvider:
    @Sendable () async -> [LogicalControllerID: ApplicationServiceDeviceDescription]
  /// Describes one controller; nil when it is not connected.
  private let descriptionProvider:
    @Sendable (LogicalControllerID) async -> ApplicationServiceDeviceDescription?
  /// Reports the session state of one controller.
  private let sessionStateProvider: @Sendable (LogicalControllerID) async -> ControllerSessionState?
  /// Builds the backend for a profile.
  private let builder: @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  /// Returns the profile that an override selects for a controller, or nil when it has none.
  private let overrideProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?
  /// The identity of the controller's custom persona, which `identityBuilder` publishes over the
  /// built-in descriptor.
  private let identityProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity?
  /// Builds the backend for a profile and a custom persona identity.
  private let identityBuilder:
    @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws -> any VirtualOutputDispatching
  /// Internal so tests can observe when a stop reaches the coordinator.
  let coordinator = AutomaticDispatcherCoordinator()
  /// Guards the mutable state below.
  private let stateLock = NSLock()
  /// Whether all virtual output is suppressed.
  private var suppressedOutput = false
  /// Whether remapping output is suppressed on the backends.
  private var remappingSuppressedOutput = false
  /// The profile that each installed backend publishes, for ``status``.
  private var diagnosticTargets: [LogicalControllerID: VirtualHIDProfileID] = [:]
  /// The publication diagnostic line of each controller, for ``status``.
  private var publicationDiagnostics: [String] = []
  /// The publication state of each controller.
  private var publicationStatuses: [LogicalControllerID: ApplicationServicePublicationStatus] = [:]
  /// Per-controller descriptions whose declared controls are fixed for the controller's binding.
  private var descriptionCache: [LogicalControllerID: ApplicationServiceDeviceDescription] = [:]
  /// Bumped by `controllerDidStop` so a description lookup in flight at that point cannot
  /// re-insert a cache entry for a controller that already stopped.
  private var descriptionCacheGeneration: [LogicalControllerID: UInt64] = [:]
  /// Controllers whose declared controls no profile can represent, surfaced through `status`.
  private var unavailableControllers: Set<LogicalControllerID> = []
  /// Each controller's selected profile and how it was selected.
  ///
  /// Selection runs once per physical session, and only a successful `retarget` changes it, so
  /// delivery never reselects.
  private var selections: [LogicalControllerID: VirtualHIDProfileSelector.Selection] = [:]
  /// The persona identity each controller's backends publish.
  ///
  /// It changes through `retarget`, which a change to the persona files triggers, and the next
  /// session reads it again.
  private var identities: [LogicalControllerID: VirtualPersona.Identity] = [:]

  /// Creates a dispatcher over `deviceManager` that builds each backend with `builder`.
  ///
  /// The providers default to the device manager; tests replace them.
  ///
  /// - Parameters:
  ///   - deviceManager: The source of controllers, sessions and ownership.
  ///   - ownershipProvider: Reports who holds a controller's input.
  ///   - builder: Builds the backend for a profile.
  ///   - descriptionsProvider: Describes every connected controller.
  ///   - overrideProvider: Returns the profile that the Advanced override selects for a controller.
  ///   - identityProvider: Returns the custom persona identity of a controller.
  ///   - identityBuilder: Builds the backend for a profile with a custom identity; defaults to
  ///     `builder`, which ignores the identity.
  init(
    deviceManager: DeviceManager,
    ownershipProvider: (@Sendable (LogicalControllerID) async -> ControllerOwnershipObservation)? =
      nil,
    builder: @escaping @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching,
    descriptionsProvider:
      (@Sendable () async -> [LogicalControllerID: ApplicationServiceDeviceDescription])? = nil,
    overrideProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? = { _ in nil
      },
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity? = { _ in
        nil
      },
    identityBuilder:
      (
        @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws ->
          any VirtualOutputDispatching
      )? = nil
  ) {
    self.deviceManager = deviceManager
    self.ownershipProvider =
      ownershipProvider ?? { identifier in await deviceManager.ownershipObservation(for: identifier)
      }
    self.descriptionsProvider =
      descriptionsProvider ?? {
        await deviceManager.connectedDeviceDescriptions().reduce(into: [:]) {
          $0[$1.logicalControllerID] = ApplicationServiceDeviceDescription(snapshot: $1)
        }
      }
    // Delivery looks up one controller per input report; building every description there
    // dominated runtime CPU.
    if let descriptionsProvider {
      self.descriptionProvider = { @Sendable identifier in
        await descriptionsProvider()[identifier]
      }
      self.sessionStateProvider = { @Sendable identifier in
        await descriptionsProvider()[identifier]?.sessionState
      }
    } else {
      self.descriptionProvider = { @Sendable identifier in
        await deviceManager.deviceDescription(for: identifier).map(
          ApplicationServiceDeviceDescription.init(snapshot:)
        )
      }
      self.sessionStateProvider = { @Sendable identifier in
        await deviceManager.controllerSessionState(for: identifier)
      }
    }
    self.builder = builder
    self.overrideProvider = overrideProvider
    self.identityProvider = identityProvider
    self.identityBuilder = identityBuilder ?? { profileID, _ in try builder(profileID) }
  }

  /// Builds a backend for the profile selected for a controller, with its persona identity.
  ///
  /// The identity is read when the backend is built, after selection recorded it.
  private func factory(
    for identifier: LogicalControllerID
  ) -> AutomaticDispatcherCoordinator.Factory {
    { [self] profileID in
      guard let identity = stateLock.withLock({ identities[identifier] }) else {
        return try builder(profileID)
      }
      return try identityBuilder(profileID, identity)
    }
  }

  /// Whether all virtual output is suppressed.
  var suppressOutput: Bool {
    get { stateLock.withLock { suppressedOutput } }
    set { stateLock.withLock { suppressedOutput = newValue } }
  }

  /// Starts the session of `identifier` and publishes its selected profile.
  ///
  /// - Throws: `CancellationError` when the dispatcher is closed, or the failure of the build.
  func activate(controller identifier: LogicalControllerID) async throws {
    let generation = cacheGeneration(for: identifier)
    try await coordinator.activateOne(

      identifier: identifier,
      descriptions: await descriptionsProvider(),
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] identifier, description in
        self?.profile(for: identifier, description: description, generation: generation)
      },
      factory: factory(for: identifier)
    )
    await synchronizeDiagnostics()
  }

  /// Publishes the selected profile of each of `identifiers`.
  ///
  /// - Throws: ``UserSpaceOutputDispatcher/CreationError/createFailed`` when the dispatcher is
  ///   closed or already holds controllers, and the failure of the first controller that fails.
  func activate(for identifiers: [LogicalControllerID]) async throws {
    let generations = stateLock.withLock {
      identifiers.reduce(into: [LogicalControllerID: UInt64]()) { generations, identifier in
        generations[identifier] = descriptionCacheGeneration[identifier, default: 0]
      }
    }
    try await coordinator.activate(
      identifiers: identifiers,
      descriptions: await descriptionsProvider(),
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] identifier, description in
        guard let self, let generation = generations[identifier] else { return nil }
        return self.profile(for: identifier, description: description, generation: generation)
      },
      factory: { [self] in factory(for: $0) }
    )
    await synchronizeDiagnostics()
  }

  /// Sets whether all virtual output is suppressed and applies it to the backends.
  func setOutputSuppressed(_ suppressed: Bool) async {
    suppressOutput = suppressed
    await coordinator.synchronizeSuppression { self.suppressOutput }
  }

  /// Sets whether remapping output is suppressed and applies it to the backends.
  func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    stateLock.withLock { remappingSuppressedOutput = suppressed }
    await coordinator.synchronizeRemappingSuppression {
      self.stateLock.withLock { self.remappingSuppressedOutput }
    }
  }
  /// The targets and publication state of the backends, as a status line.
  var status: VirtualOutputBackendStatus {
    stateLock.withLock {
      let targets = Set(diagnosticTargets.values.map(\.rawValue)).sorted()
      let suffix = targets.isEmpty ? "" : ", targets: \(targets.joined(separator: "; "))"
      let diagnostics =
        publicationDiagnostics.isEmpty
        ? "" : ", publication: \(publicationDiagnostics.joined(separator: "; "))"
      let unavailable =
        unavailableControllers.isEmpty ? "" : ", unavailable: \(unavailableControllers.count)"
      return .backend("automatic\(suffix)\(diagnostics)\(unavailable)")
    }
  }
  /// Always nil: the automatic dispatcher reports no rumble status.
  var lastRumbleStatus: String? { nil }
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
    await synchronizeDiagnostics()
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
  /// A neutral state goes only to an existing backend and never creates one.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when no backend can take the state, or
  ///   the failure of the backend, which also starts recovery of the publication.
  func send(_ state: RemappingGamepadState, for identifier: LogicalControllerID) async throws {
    guard state == .neutral else {
      try await activate(controller: identifier)

      try await deliver(.remapped(state), from: identifier)
      return
    }
    guard let lease = await coordinator.leaseForNeutralization(identifier) else { return }
    do {
      await coordinator.recordPublicationAttempt(for: identifier)
      guard let sink = lease.backend as? any RemappingGamepadSink else {
        throw RemappingEventEngineError.sinkUnavailable
      }
      try await sink.send(state, for: identifier)
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
  private func deliver(
    _ delivery: AutomaticOutputDelivery,
    from identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void = {}
  ) async throws {
    await coordinator.synchronizeSuppression { self.suppressOutput }
    let generation = cacheGeneration(for: identifier)
    guard let description = await cachedDescription(for: identifier),
      let profile = profile(for: identifier, description: description, generation: generation),
      let lease = await coordinator.leaseForDispatch(
        controller: identifier,
        profile: profile,
        isEligible: { [weak self] identifier, profile in
          await self?.isEligible(identifier, profile: profile) ?? false
        },
        factory: factory(for: identifier)
      )
    else { throw RemappingEventEngineError.sinkUnavailable }
    do {
      await coordinator.recordPublicationAttempt(for: identifier)
      try await delivery.publish(
        through: lease.backend,
        for: identifier,
        onPublished: onPublished
      )
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

  /// Records whether another client holds the input of `identifier`.
  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async {
    await coordinator.setHeldByAnotherClient(ownership == .ownedByAnotherClient, for: identifier)
    await synchronizeDiagnostics()
  }

  /// Forgets the selection of `identifier` and stops its session.
  func controllerDidStop(_ identifier: LogicalControllerID) async {
    stateLock.withLock {
      _ = descriptionCache.removeValue(forKey: identifier)
      descriptionCacheGeneration[identifier, default: 0] &+= 1
      _ = unavailableControllers.remove(identifier)
      _ = selections.removeValue(forKey: identifier)
      _ = identities.removeValue(forKey: identifier)
    }
    await coordinator.stop(identifier)
    await synchronizeDiagnostics()
  }

  /// Copies the coordinator state into the status and posts a change when it differs.
  private func synchronizeDiagnostics() async {
    let targets = await coordinator.installedTargets()
    let publication = await coordinator.publicationDiagnostics()
    let statuses = await coordinator.publicationStatuses()
    let changed = stateLock.withLock { () -> Bool in
      let changed =
        diagnosticTargets != targets || publicationDiagnostics != publication
        || publicationStatuses != statuses
      diagnosticTargets = targets
      publicationDiagnostics = publication
      publicationStatuses = statuses
      return changed
    }
    if changed { NotificationCenter.postServiceStatusChanged(from: self) }
  }

  /// The controller's selected profile; nil when no virtual profile can represent its declared
  /// controls, which leaves the controller without a virtual device.
  ///
  /// Selects only when the physical session has no selection yet.
  private func profile(
    for identifier: LogicalControllerID,
    description: ApplicationServiceDeviceDescription,
    generation: UInt64
  ) -> VirtualHIDProfileID? {
    if let selection = stateLock.withLock({ selections[identifier] }) { return selection.profileID }
    let selection = select(for: description)
    commit(
      selection,
      identity: identityProvider(description),
      for: identifier,
      generation: generation
    )
    return selection?.profileID
  }

  /// The persona the serving policy decides OJD publishes for the controller, from its declared
  /// controls and its Advanced override; nil when no persona can represent it.
  private func select(
    for description: ApplicationServiceDeviceDescription
  ) -> VirtualHIDProfileSelector.Selection? {
    ServingPolicy.publishedPersona(for: description, override: overrideProvider(description))
  }

  /// Records the controller's selection, or records it as unavailable when no profile can represent
  /// it so `status` surfaces the failure instead of the dispatcher silently leaving the controller
  /// without a virtual device.
  ///
  /// A controller that stopped since `generation` was read keeps no entry.
  private func commit(
    _ selection: VirtualHIDProfileSelector.Selection?,
    identity: VirtualPersona.Identity?,
    for identifier: LogicalControllerID,
    generation: UInt64
  ) {
    let changed = stateLock.withLock { () -> Bool in
      guard descriptionCacheGeneration[identifier, default: 0] == generation else { return false }
      let previous = selections[identifier]
      let wasUnavailable = unavailableControllers.contains(identifier)
      identities[identifier] = identity
      if let selection {
        selections[identifier] = selection
        _ = unavailableControllers.remove(identifier)
      } else {
        _ = selections.removeValue(forKey: identifier)
        _ = unavailableControllers.insert(identifier)
      }
      return previous?.profileID != selection?.profileID || previous?.source != selection?.source
        || wasUnavailable != (selection == nil)
    }
    if changed { NotificationCenter.postServiceStatusChanged(from: self) }
  }

  /// The generation of the description cache of `identifier`.
  private func cacheGeneration(for identifier: LogicalControllerID) -> UInt64 {
    stateLock.withLock { descriptionCacheGeneration[identifier, default: 0] }
  }

  /// How the current profile of a controller was selected.
  ///
  /// Nil before selection or when no profile can represent the controller.
  func selectionSource(
    for identifier: LogicalControllerID
  ) -> VirtualHIDProfileSelector.Selection.Source? {
    stateLock.withLock { selections[identifier]?.source }
  }

  /// The current selection of `identifier`, and whether no profile can represent it.
  func profileState(
    for identifier: LogicalControllerID
  ) -> (selection: VirtualHIDProfileSelector.Selection?, unavailable: Bool) {
    stateLock.withLock {
      (selections[identifier], unavailableControllers.contains(identifier))
    }
  }

  /// The publication state of `identifier` at the last delivery, activation, or stop; nil before
  /// the controller has a target profile.
  func publicationStatus(
    for identifier: LogicalControllerID
  ) -> ApplicationServicePublicationStatus? {
    stateLock.withLock { publicationStatuses[identifier] }
  }

  /// The values the virtual gamepad of a controller last reported.
  ///
  /// Nil when no user-space virtual gamepad publishes it.
  func virtualOutputState(for identifier: LogicalControllerID) async -> VirtualGamepadState? {
    guard let backend = await coordinator.installedBackend(for: identifier) else { return nil }
    return (backend as? UserSpaceOutputDispatcher)?.virtualOutputState(for: identifier)
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
  /// suppression, recovery, or before activation) publishes the selection when it next installs.
  func retarget(controller identifier: LogicalControllerID) async throws {
    let generation = cacheGeneration(for: identifier)
    guard let description = await cachedDescription(for: identifier),
      let selection = select(for: description)
    else { return }
    let (current, liveIdentity) = stateLock.withLock {
      (selections[identifier], identities[identifier])
    }
    let currentIdentity = identityProvider(description)
    let identityChanged = currentIdentity != liveIdentity
    guard current != selection || identityChanged else { return }
    var identity = liveIdentity
    if current?.profileID != selection.profileID || identityChanged {
      // The replacement is built with the current persona identity. The identity is fixed
      // when a device is created, so an identity change alone rebuilds the same profile.
      identity = currentIdentity
      stateLock.withLock { identities[identifier] = identity }
      do {
        try await coordinator.retarget(
          identifier,
          target: selection.profileID,
          rebuildsLiveTarget: identityChanged,
          isEligible: { [weak self] identifier, profile in
            await self?.isEligible(identifier, profile: profile) ?? false
          },
          factory: factory(for: identifier)
        )
      } catch {
        stateLock.withLock { identities[identifier] = liveIdentity }
        await synchronizeDiagnostics()
        throw error
      }
    }
    commit(selection, identity: identity, for: identifier, generation: generation)
    await synchronizeDiagnostics()
  }

  /// Returns the cached description of `identifier`, reading it first when it is not cached.
  private func cachedDescription(
    for identifier: LogicalControllerID
  ) async -> ApplicationServiceDeviceDescription? {
    if let cached = stateLock.withLock({ descriptionCache[identifier] }) { return cached }
    let generation = stateLock.withLock { descriptionCacheGeneration[identifier, default: 0] }
    guard let description = await descriptionProvider(identifier) else { return nil }
    stateLock.withLock {
      if descriptionCacheGeneration[identifier, default: 0] == generation {
        descriptionCache[identifier] = description
      }
    }
    return description
  }

  /// Whether `identifier` has an active session and the serving policy publishes `profile` for it.
  private func isEligible(
    _ identifier: LogicalControllerID,
    profile: VirtualHIDProfileID
  ) async -> Bool {
    guard let description = await cachedDescription(for: identifier),
      await sessionStateProvider(identifier) == .active
    else { return false }
    var input = ServingInput(description, override: profile)
    input.observation = await ownershipProvider(identifier)
    return ServingPolicy.route(input).publishesVirtualDevice
  }

  /// Closes the coordinator and clears the cache.
  func close() async {
    await coordinator.close()
    stateLock.withLock { descriptionCache.removeAll() }
  }
}
