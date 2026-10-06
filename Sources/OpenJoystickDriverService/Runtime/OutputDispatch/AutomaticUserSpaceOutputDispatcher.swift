import Foundation
import OpenJoystickDriverKit

final class AutomaticUserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, ControllerLifecycleListener, RemappingGamepadSink,
  RemappingGamepadOutputControlling, @unchecked Sendable
{
  private let deviceManager: DeviceManager
  private let ownershipProvider:
    @Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation
  private let descriptionsProvider: @Sendable () async -> [ApplicationServiceDeviceDescription]
  private let descriptionProvider:
    @Sendable (DeviceIdentifier) async -> ApplicationServiceDeviceDescription?
  private let sessionStateProvider: @Sendable (DeviceIdentifier) async -> ControllerSessionState?
  private let builder: @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  private let overrideProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?
  /// The identity of the controller's custom persona, which `identityBuilder` publishes over the
  /// built-in descriptor.
  private let identityProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity?
  private let identityBuilder:
    @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws -> any VirtualOutputDispatching
  /// Internal so tests can observe when a stop reaches the coordinator.
  let coordinator = AutomaticDispatcherCoordinator()
  private let stateLock = NSLock()
  private var suppressedOutput = false
  private var remappingSuppressedOutput = false
  private var diagnosticTargets: [DeviceIdentifier: VirtualHIDProfileID] = [:]
  private var publicationDiagnostics: [String] = []
  private var publicationStatuses: [DeviceIdentifier: ApplicationServicePublicationStatus] = [:]
  /// Per-controller descriptions whose declared controls are fixed for the controller's binding.
  private var descriptionCache: [DeviceIdentifier: ApplicationServiceDeviceDescription] = [:]
  /// Bumped by `controllerDidStop` so a description lookup in flight at that point cannot
  /// re-insert a cache entry for a controller that already stopped.
  private var descriptionCacheGeneration: [DeviceIdentifier: UInt64] = [:]
  /// Controllers whose declared controls no profile can represent, surfaced through `status`.
  private var unavailableControllers: Set<DeviceIdentifier> = []
  /// Each controller's selected profile and how it was selected. Selection runs once per
  /// physical session, and only a successful `retarget` changes it, so delivery never reselects.
  private var selections: [DeviceIdentifier: VirtualHIDProfileSelector.Selection] = [:]
  /// The persona identity each controller's backends publish. It changes with `selections`, so a
  /// persona edited while the controller is connected applies from its next session.
  private var identities: [DeviceIdentifier: VirtualPersona.Identity] = [:]

  init(
    deviceManager: DeviceManager,
    ownershipProvider: (@Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation)? =
      nil,
    builder: @escaping @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching,
    descriptionsProvider: (@Sendable () async -> [ApplicationServiceDeviceDescription])? = nil,
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
        await deviceManager.connectedDeviceDescriptions().map(
          ApplicationServiceDeviceDescription.init(snapshot:)
        )
      }
    // Delivery looks up one controller per input report; building every description there
    // dominated runtime CPU.
    if let descriptionsProvider {
      self.descriptionProvider = { @Sendable identifier in
        await descriptionsProvider().first { $0.runtimeIdentifier == identifier.runtimeIdentifier }
      }
      self.sessionStateProvider = { @Sendable identifier in
        await descriptionsProvider().first { $0.runtimeIdentifier == identifier.runtimeIdentifier }?
          .sessionState
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

  /// Builds a backend for `identifier`'s selected profile, with its persona identity when it has
  /// one. The identity is read when the backend is built, after selection recorded it.
  private func factory(for identifier: DeviceIdentifier) -> AutomaticDispatcherCoordinator.Factory {
    { [self] profileID in
      guard let identity = stateLock.withLock({ identities[identifier] }) else {
        return try builder(profileID)
      }
      return try identityBuilder(profileID, identity)
    }
  }

  var suppressOutput: Bool {
    get { stateLock.withLock { suppressedOutput } }
    set { stateLock.withLock { suppressedOutput = newValue } }
  }

  func activate(controller identifier: DeviceIdentifier) async throws {
    let generation = cacheGeneration(for: identifier)
    try await coordinator.activateOne(

      identifier: identifier,
      descriptions: await descriptionsProvider(),
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] description in
        self?.profile(for: identifier, description: description, generation: generation)
      },
      factory: factory(for: identifier)
    )
    await synchronizeDiagnostics()
  }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    let generations = stateLock.withLock {
      identifiers.reduce(into: [DeviceIdentifier: UInt64]()) { generations, identifier in
        generations[identifier] = descriptionCacheGeneration[identifier, default: 0]
      }
    }
    try await coordinator.activate(
      identifiers: identifiers,
      descriptions: await descriptionsProvider(),
      isEligible: { [weak self] identifier, profile in
        await self?.isEligible(identifier, profile: profile) ?? false
      },
      profileProvider: { [weak self] description in
        guard let self,
          let identifier = identifiers.first(where: {
            $0.runtimeIdentifier == description.runtimeIdentifier
          }), let generation = generations[identifier]
        else { return nil }
        return self.profile(for: identifier, description: description, generation: generation)
      },
      factory: { [self] in factory(for: $0) }
    )
    await synchronizeDiagnostics()
  }

  func setOutputSuppressed(_ suppressed: Bool) async {
    suppressOutput = suppressed
    await coordinator.synchronizeSuppression { self.suppressOutput }
  }

  func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    stateLock.withLock { remappingSuppressedOutput = suppressed }
    await coordinator.synchronizeRemappingSuppression {
      self.stateLock.withLock { self.remappingSuppressedOutput }
    }
  }
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
  var lastRumbleStatus: String? { nil }
  func dispatch(
    _ event: ControllerEvent,
    labels: ControllerButtonLabels,
    from identifier: DeviceIdentifier
  ) async {
    try? await deliver(.input(event, labels), from: identifier)
    await synchronizeDiagnostics()
  }

  /// Activation marks the start of a controller session, so it also starts a new physical
  /// session for a controller whose earlier session stopped.
  func activateOutput(for identifier: DeviceIdentifier) async {
    await coordinator.beginSession(identifier)
    try? await deliver(.activation, from: identifier)
    await synchronizeDiagnostics()
  }

  func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
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

  private func deliver(
    _ delivery: AutomaticOutputDelivery,
    from identifier: DeviceIdentifier
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
      try await delivery.publish(through: lease.backend, for: identifier)
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

  func controllerDidStop(_ identifier: DeviceIdentifier) async {
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

  private func synchronizeDiagnostics() async {
    let targets = await coordinator.installedTargets()
    let publication = await coordinator.publicationDiagnostics()
    let statuses = await coordinator.publicationStatuses()
    stateLock.withLock {
      diagnosticTargets = targets
      publicationDiagnostics = publication
      publicationStatuses = statuses
    }
  }

  /// The controller's selected profile; nil when no virtual profile can represent its declared
  /// controls, which leaves the controller without a virtual device. Selects only when the
  /// physical session has no selection yet.
  private func profile(
    for identifier: DeviceIdentifier,
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

  /// Selection from the controller's declared controls and its Advanced override.
  private func select(
    for description: ApplicationServiceDeviceDescription
  ) -> VirtualHIDProfileSelector.Selection? {
    try? VirtualHIDProfileSelector.select(
      controls: description.capabilities.controls,
      override: overrideProvider(description)
    )
  }

  /// Records the controller's selection, or records it as unavailable when no profile can
  /// represent it so `status` surfaces the failure instead of the dispatcher silently leaving the
  /// controller without a virtual device. A controller that stopped since `generation` was read
  /// keeps no entry.
  private func commit(
    _ selection: VirtualHIDProfileSelector.Selection?,
    identity: VirtualPersona.Identity?,
    for identifier: DeviceIdentifier,
    generation: UInt64
  ) {
    stateLock.withLock {
      guard descriptionCacheGeneration[identifier, default: 0] == generation else { return }
      identities[identifier] = identity
      if let selection {
        selections[identifier] = selection
        _ = unavailableControllers.remove(identifier)
      } else {
        _ = selections.removeValue(forKey: identifier)
        _ = unavailableControllers.insert(identifier)
      }
    }
  }

  private func cacheGeneration(for identifier: DeviceIdentifier) -> UInt64 {
    stateLock.withLock { descriptionCacheGeneration[identifier, default: 0] }
  }

  /// How `identifier`'s current profile was selected; nil before selection or when no profile
  /// can represent the controller.
  func selectionSource(
    for identifier: DeviceIdentifier
  ) -> VirtualHIDProfileSelector.Selection.Source? {
    stateLock.withLock { selections[identifier]?.source }
  }

  /// The current selection of the controller with `runtimeIdentifier`, and whether no profile can
  /// represent it.
  func profileState(
    runtimeIdentifier: String
  ) -> (selection: VirtualHIDProfileSelector.Selection?, unavailable: Bool) {
    stateLock.withLock {
      (
        selections.first { $0.key.runtimeIdentifier == runtimeIdentifier }?.value,
        unavailableControllers.contains { $0.runtimeIdentifier == runtimeIdentifier }
      )
    }
  }

  /// The publication state of the controller with `runtimeIdentifier` at the last delivery,
  /// activation, or stop; nil before the controller has a target profile.
  func publicationStatus(runtimeIdentifier: String) -> ApplicationServicePublicationStatus? {
    stateLock.withLock {
      publicationStatuses.first { $0.key.runtimeIdentifier == runtimeIdentifier }?.value
    }
  }

  /// The values the matching controller's virtual gamepad last reported; nil when no user-space
  /// virtual gamepad publishes it.
  func virtualOutputState(
    matching model: DeviceIdentifier,
    runtimeIdentifier: String?
  ) async -> VirtualGamepadState? {
    guard
      let installed = await coordinator.installedBackend(
        matching: model,
        runtimeIdentifier: runtimeIdentifier
      )
    else { return nil }
    return (installed.backend as? UserSpaceOutputDispatcher)?.virtualOutputState(
      for: installed.controller
    )
  }

  /// Reselects the profile for one controller and, when the profile changes, replaces only that
  /// controller's backend. The new selection is recorded only once the replacement succeeds.
  ///
  /// The replacement is built and activated while the live backend keeps publishing, and the
  /// live backend is neutralized before it is retired; when the replacement cannot be built or
  /// activated, the live backend and its selection stay and the error is rethrown. The cost of
  /// that order: for a moment both virtual devices exist with the same serial number and
  /// LocationID, and consumers may see a second pad. A controller with no live backend (during
  /// suppression, recovery, or before activation) publishes the new profile when it next installs.
  func retarget(controller identifier: DeviceIdentifier) async throws {
    let generation = cacheGeneration(for: identifier)
    guard let description = await cachedDescription(for: identifier),
      let selection = select(for: description)
    else { return }
    let (current, liveIdentity) = stateLock.withLock {
      (selections[identifier], identities[identifier])
    }
    guard current != selection else { return }
    var identity = liveIdentity
    if current?.profileID != selection.profileID {
      // The replacement is built with the persona identity of the new selection.
      identity = identityProvider(description)
      stateLock.withLock { identities[identifier] = identity }
      do {
        try await coordinator.retarget(
          identifier,
          target: selection.profileID,
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

  private func cachedDescription(
    for identifier: DeviceIdentifier
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

  private func isEligible(
    _ identifier: DeviceIdentifier,
    profile: VirtualHIDProfileID
  ) async -> Bool {
    guard await cachedDescription(for: identifier) != nil,
      await sessionStateProvider(identifier) == .active
    else { return false }
    let ownership = await ownershipProvider(identifier)
    return ControllerExposureDecision.decide(ownership: ownership, intent: .profile(profile))
      .eligibility == .eligible
  }

  func close() async {
    await coordinator.close()
    stateLock.withLock { descriptionCache.removeAll() }
  }
}
