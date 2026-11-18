import Foundation
import OpenJoystickDriverKit

extension AutomaticDispatcherCoordinator {
  /// Decides whether a controller may publish a profile.
  typealias Eligibility = @Sendable (LogicalControllerID, VirtualHIDProfileID) async -> Bool
  /// Builds the backend that publishes a profile.
  typealias Factory = @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  /// The controller's selected profile; nil when no profile can represent it.
  typealias ProfileProvider =
    @Sendable (LogicalControllerID, ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?

  /// An installation request for a controller, valid only for the generations it carries.
  struct Request: Sendable {
    /// The controller that the backend publishes for.
    let controller: LogicalControllerID
    /// The identity of the request, which the installed backend records.
    let token: UUID
    /// The physical session generation that the request belongs to.
    let sessionGeneration: UInt64
    /// The publication generation that the request belongs to.
    let publicationGeneration: UInt64
    /// The profile to publish.
    let target: VirtualHIDProfileID
  }

  /// An installation in flight.
  struct Pending {
    /// The request that the task serves.
    let request: Request
    /// The task that builds, activates and installs the backend.
    let task: Task<Void, any Error>
  }

  /// The publication state of one controller.
  struct Entry {
    /// Physical-session state survives temporary publication suppression.
    var sessionGeneration: UInt64 = 0
    /// Whether the physical session is live.
    var physicalSessionActive = true
    /// Invalidates only virtual publication work for the current physical session.
    var publicationGeneration: UInt64 = 0
    /// The profile that the installed backend publishes.
    var target: VirtualHIDProfileID?
    /// How to publish again after a failure or a suppression.
    var context: PublicationContext?
    /// The backend that publishes.
    var installed: AutomaticBackendSlot?
    /// The token of the request that installed the backend.
    var installedToken: UUID?
    /// The backend that is closing and must finish before another publishes.
    var retiring: AutomaticBackendSlot?
    /// The installation in flight that is current.
    var pending: Pending?
    /// Every installation in flight, by request token.
    var tasks: [UUID: Pending] = [:]
    /// When a send was last attempted, in uptime nanoseconds.
    var lastAttemptedSend: UInt64?
    /// When a send last completed, in uptime nanoseconds.
    var lastCompletedSend: UInt64?
    /// The text of the last publication failure.
    var lastFailure: String?
    /// Where recovery stands: idle, retiring, waiting-for-retirement, retry-gated or recovering.
    var recoveryState = "idle"
    /// The identity of the scheduled retry, so a stale retry does nothing.
    var recoveryToken: UUID?
    /// Another client holds the controller's input; nothing installs until it lets go.
    var heldByAnotherClient = false
  }

  /// What a controller needs to publish again without a caller.
  struct PublicationContext: Sendable {
    /// The profile to publish.
    let target: VirtualHIDProfileID
    /// Decides whether the controller may publish.
    let isEligible: Eligibility
    /// Builds the backend.
    let factory: Factory
  }

  /// Starts the session of `identifier` and publishes its selected profile.
  ///
  /// A controller without a profile publishes nothing.
  ///
  /// - Throws: `CancellationError` when the coordinator is closed, or the failure of the build.
  func activateOne(
    identifier: LogicalControllerID,
    descriptions: [LogicalControllerID: ApplicationServiceDeviceDescription],
    isEligible: @escaping Eligibility,
    profileProvider: ProfileProvider,
    factory: @escaping Factory
  ) async throws {
    guard !closed else { throw CancellationError() }
    guard
      let description = descriptions[identifier],
      let profile = profileProvider(identifier, description)
    else { return }
    beginSession(identifier)
    await setHeldByAnotherClient(
      description.hidInputOwnership == .ownedByAnotherClient,
      for: identifier
    )
    let lease = try await acquire(
      identifier,
      target: profile,
      isEligible: isEligible,
      factory: factory
    )
    await lease?.release()
  }

  /// Begins a physical session for a controller that `stop` ended, as when the same controller
  /// starts again after system sleep.
  ///
  /// Work from the ended session stays invalid.
  func beginSession(_ identifier: LogicalControllerID) {
    guard !closed, entries[identifier]?.physicalSessionActive == false else { return }
    entries[identifier]?.physicalSessionActive = true
    entries[identifier]?.sessionGeneration &+= 1
    entries[identifier]?.publicationGeneration &+= 1
  }

  /// Publishes the profile of each of `identifiers` once, closing the coordinator when one fails.
  ///
  /// - Throws: ``UserSpaceOutputDispatcher/CreationError/createFailed`` when the coordinator is
  ///   closed or already holds controllers, and the failure of the first controller that fails.
  func activate(
    identifiers: [LogicalControllerID],
    descriptions: [LogicalControllerID: ApplicationServiceDeviceDescription],
    isEligible: @escaping Eligibility,
    profileProvider: @escaping ProfileProvider,
    factory: (LogicalControllerID) -> Factory
  ) async throws {
    guard !closed, entries.isEmpty else {
      throw UserSpaceOutputDispatcher.CreationError.createFailed
    }
    var seen = Set<LogicalControllerID>()
    do {
      for identifier in identifiers where seen.insert(identifier).inserted {
        try await activateOne(
          identifier: identifier,
          descriptions: descriptions,
          isEligible: isEligible,
          profileProvider: profileProvider,
          factory: factory(identifier)
        )
      }
    } catch {
      await close()
      throw error
    }
  }

  /// Acquires only an existing backend so cleanup cannot create a replacement controller.
  func leaseForNeutralization(_ controller: LogicalControllerID) async -> AutomaticBackendLease? {
    if closed {
      await close()
      return nil
    }
    if let lease = entries[controller]?.installed?.acquire() { return lease }
    _ = await entries[controller]?.retiring?.retireAndWait()
    return nil
  }

  /// Returns a lease on the backend that publishes `profile` for `controller`, or nil when none
  /// can.
  func leaseForDispatch(
    controller: LogicalControllerID,
    profile: VirtualHIDProfileID,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory
  ) async -> AutomaticBackendLease? {
    try? await acquire(controller, target: profile, isEligible: isEligible, factory: factory)
  }

  /// Replaces the controller's live backend with one for `target`, keeping the live backend
  /// publishing until the replacement has activated.
  ///
  /// A live backend that already publishes `target` is left unchanged unless `rebuildsLiveTarget`
  /// is set, as when only the persona identity changed, which is fixed when the device is created.
  /// Without a live backend, as during suppression or recovery, the publication context adopts
  /// `target`, so the next installation publishes it.
  ///
  /// - Throws: The build or activation failure, or `CancellationError` when the controller
  ///   stopped, the coordinator closed, or the replacement could not be installed.
  func retarget(
    _ controller: LogicalControllerID,
    target: VirtualHIDProfileID,
    rebuildsLiveTarget: Bool = false,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory
  ) async throws {
    guard !closed else { throw CancellationError() }
    // Let an installation in flight settle, so it is replaced rather than raced.
    if let pending = entries[controller]?.pending { _ = await pending.task.result }
    guard !closed else { throw CancellationError() }
    guard let entry = entries[controller] else { return }
    guard entry.installed != nil, let current = entry.target else {
      if entry.context != nil {
        entries[controller]?.context = PublicationContext(
          target: target,
          isEligible: isEligible,
          factory: factory
        )
      }
      return
    }
    guard current != target || rebuildsLiveTarget else { return }
    let lease = try await acquire(
      controller,
      target: target,
      isEligible: isEligible,
      factory: factory,
      replacesLiveBackend: true
    )
    guard let lease else { throw CancellationError() }
    await lease.release()
  }

  /// Returns a lease on the backend that publishes `target`, installing or replacing it as needed.
  ///
  /// Nil when the coordinator is closed or suppressed, the session ended, another client holds the
  /// controller, or the controller is not eligible. A caller that finds a request for the same
  /// target in flight waits for it.
  ///
  /// - Throws: `CancellationError` when the generations changed while the request ran, or the
  ///   failure of the build or activation.
  func acquire(
    _ controller: LogicalControllerID,
    target: VirtualHIDProfileID,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory,
    replacesLiveBackend: Bool = false
  ) async throws -> AutomaticBackendLease? {
    guard !closed else { return nil }
    if entries[controller] == nil { entries[controller] = Entry() }
    guard !suppressed, let initial = entries[controller], initial.physicalSessionActive else {
      return nil
    }
    if initial.heldByAnotherClient {
      // The context keeps the target, so the status names what publishes after the release.
      entries[controller]?.context =
        initial.context
        ?? PublicationContext(target: target, isEligible: isEligible, factory: factory)
      return nil
    }
    let sessionGeneration = initial.sessionGeneration
    let publicationGeneration = initial.publicationGeneration
    guard await isEligible(controller, target) else { return nil }
    guard !closed, let current = entries[controller], current.physicalSessionActive,
      current.sessionGeneration == sessionGeneration,
      current.publicationGeneration == publicationGeneration, !suppressed
    else { throw CancellationError() }
    if !replacesLiveBackend, current.target == target, let lease = current.installed?.acquire() {
      return lease
    }

    let pending: Pending
    if let existing = current.pending, existing.request.target == target {
      pending = existing
    } else {
      current.pending?.task.cancel()
      let request = Request(
        controller: controller,
        token: UUID(),
        sessionGeneration: sessionGeneration,
        publicationGeneration: publicationGeneration,
        target: target
      )
      let predecessors = current.tasks.values.map(\.task)
      let context = PublicationContext(target: target, isEligible: isEligible, factory: factory)
      // Factories may synchronously block in native creation. Keep them off the coordinator and
      // the cooperative pool.
      let task = Task { [self] in
        try Task.checkCancellation()
        let candidate = AutomaticBackendSlot(
          try await BlockingWork.run(label: "com.openjoystickdriver.output.factory") {
            try factory(target)
          }
        )
        do {
          for predecessor in predecessors { _ = await predecessor.result }
          if replacesLiveBackend {
            try await replace(with: candidate, request: request, context: context)
          } else {
            try await install(candidate, request: request, factory: factory)
          }
        } catch {
          _ = await candidate.retireAndWait()
          throw error
        }
      }
      pending = Pending(request: request, task: task)
      // A replacement adopts its context only once it is live, so a failed one leaves recovery
      // targeting the backend that stayed live.
      if !replacesLiveBackend { entries[controller]?.context = context }
      entries[controller]?.pending = pending
      entries[controller]?.tasks[request.token] = pending
    }
    defer {
      entries[controller]?.tasks[pending.request.token] = nil
      if entries[controller]?.pending?.request.token == pending.request.token {
        entries[controller]?.pending = nil
      }
    }
    try await pending.task.value
    guard !closed, let installed = entries[controller], installed.physicalSessionActive,
      installed.sessionGeneration == sessionGeneration,
      installed.publicationGeneration == publicationGeneration, installed.target == target,
      installed.installedToken == pending.request.token
    else { throw CancellationError() }
    return installed.installed?.acquire()
  }

  /// Throws `CancellationError` unless `request` is still the current request of its controller.
  private func validate(_ request: Request) throws {
    try Task.checkCancellation()
    guard !closed, !suppressed, let entry = entries[request.controller],
      entry.physicalSessionActive, entry.sessionGeneration == request.sessionGeneration,
      entry.publicationGeneration == request.publicationGeneration,
      entry.pending?.request.token == request.token
    else { throw CancellationError() }
  }

  /// Installs `candidate` for `request` after the previous backend has retired.
  ///
  /// A failed activation restores the previous target.
  ///
  /// - Throws: `CancellationError` when the request is stale or the previous backend does not
  ///   close, and the failure of the activation.
  private func install(
    _ candidate: AutomaticBackendSlot,
    request: Request,
    factory: @escaping Factory
  ) async throws {
    try validate(request)
    let previousTarget = entries[request.controller]?.target
    let old = entries[request.controller]?.installed ?? entries[request.controller]?.retiring
    entries[request.controller]?.retiring = old
    entries[request.controller]?.installed = nil
    entries[request.controller]?.installedToken = nil
    entries[request.controller]?.target = nil
    if let old {
      guard await old.retireAndWait() else {
        _ = await candidate.retireAndWait()
        throw CancellationError()
      }
      try validate(request)
      entries[request.controller]?.retiring = nil
    }
    do {
      try await activateAndSynchronize(candidate, request: request)
      entries[request.controller]?.installed = candidate
      entries[request.controller]?.installedToken = request.token
      entries[request.controller]?.target = request.target
    } catch {
      _ = await candidate.retireAndWait()
      if let previousTarget {
        await restore(target: previousTarget, request: request, factory: factory)
      }
      throw error
    }
  }

  /// Activates `candidate` beside the live backend, then neutralizes and retires the live one, so
  /// a candidate that fails to activate leaves the previous backend publishing.
  private func replace(
    with candidate: AutomaticBackendSlot,
    request: Request,
    context: PublicationContext
  ) async throws {
    try validate(request)
    // A slot still retiring from an earlier replacement finishes before this one takes its place.
    if let earlier = entries[request.controller]?.retiring {
      // Never publish beside a device that has not finished closing. The live backend keeps
      // publishing, and the slot clears once its forced close completes.
      guard await earlier.retireAndWait() else {
        clearRetirementOnceClosed(earlier, controller: request.controller)
        throw CancellationError()
      }
      if entries[request.controller]?.retiring === earlier {
        entries[request.controller]?.retiring = nil
      }
      try validate(request)
    }
    try await activateAndSynchronize(candidate, request: request)
    let old = entries[request.controller]?.installed
    entries[request.controller]?.installed = candidate
    entries[request.controller]?.installedToken = request.token
    entries[request.controller]?.target = request.target
    entries[request.controller]?.context = context
    guard let old else { return }
    entries[request.controller]?.retiring = old
    await neutralize(old, controller: request.controller)
    guard await old.retireAndWait() else {
      clearRetirementOnceClosed(old, controller: request.controller)
      return
    }
    guard entries[request.controller]?.retiring === old else { return }
    entries[request.controller]?.retiring = nil
  }

  /// Returns the controller's virtual device to rest before its backend is retired, so no
  /// consumer is left holding pressed input from a device that disappears.
  private func neutralize(_ slot: AutomaticBackendSlot, controller: LogicalControllerID) async {
    guard let lease = slot.acquire() else { return }
    if let sink = lease.backend as? any RemappingGamepadSink {
      try? await sink.send(RemappingGamepadState.neutral, for: controller)
    }
    await lease.release()
  }

  /// Activates `candidate` and applies the current suppression, repeating when it changed
  /// meanwhile.
  private func activateAndSynchronize(
    _ candidate: AutomaticBackendSlot,
    request: Request
  ) async throws {
    try await candidate.backend.activate(for: [request.controller])
    try validate(request)
    repeat {
      let revision = suppressionRevision
      await candidate.backend.setOutputSuppressed(suppressed)
      if let control = candidate.backend as? any RemappingGamepadOutputControlling {
        await control.setRemappingOutputSuppressed(remappingSuppressed)
      }
      try validate(request)
      if revision == suppressionRevision { break }
    } while true
  }

  /// Publishes `target` again on a backend that rolls back a failed installation.
  private func restore(
    target: VirtualHIDProfileID,
    request: Request,
    factory: Factory
  ) async {
    guard (try? validate(request)) != nil, let backend = try? factory(target) else { return }
    let rollback = AutomaticBackendSlot(backend)
    do {
      try await activateAndSynchronize(rollback, request: request)
      entries[request.controller]?.installed = rollback
      entries[request.controller]?.installedToken = nil
      entries[request.controller]?.target = target
    } catch { _ = await rollback.retireAndWait() }
  }
}
