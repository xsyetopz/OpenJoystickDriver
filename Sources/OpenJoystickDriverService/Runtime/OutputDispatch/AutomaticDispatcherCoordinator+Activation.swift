import Foundation
import OpenJoystickDriverKit

extension AutomaticDispatcherCoordinator {
  typealias Eligibility = @Sendable (DeviceIdentifier, VirtualHIDProfileID) async -> Bool
  typealias Factory = @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  /// The controller's selected profile; nil when no profile can represent it.
  typealias ProfileProvider =
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?

  struct Request: Sendable {
    let controller: DeviceIdentifier
    let token: UUID
    let sessionGeneration: UInt64
    let publicationGeneration: UInt64
    let target: VirtualHIDProfileID
  }

  struct Pending {
    let request: Request
    let task: Task<Void, Error>
  }

  struct Entry {
    /// Physical-session state survives temporary publication suppression.
    var sessionGeneration: UInt64 = 0
    var physicalSessionActive = true
    /// Invalidates only virtual publication work for the current physical session.
    var publicationGeneration: UInt64 = 0
    var target: VirtualHIDProfileID?
    var context: PublicationContext?
    var installed: AutomaticBackendSlot?
    var installedToken: UUID?
    var retiring: AutomaticBackendSlot?
    var pending: Pending?
    var tasks: [UUID: Pending] = [:]
    var lastAttemptedSend: UInt64?
    var lastCompletedSend: UInt64?
    var lastFailure: String?
    var recoveryState = "idle"
    var recoveryToken: UUID?
  }

  struct PublicationContext: Sendable {
    let target: VirtualHIDProfileID
    let isEligible: Eligibility
    let factory: Factory
  }

  func activateOne(
    identifier: DeviceIdentifier,
    descriptions: [ApplicationServiceDeviceDescription],
    isEligible: @escaping Eligibility,
    profileProvider: @escaping ProfileProvider,
    factory: @escaping Factory
  ) async throws {
    guard !closed else { throw CancellationError() }
    guard
      let description = descriptions.first(where: {
        $0.runtimeIdentifier == identifier.runtimeIdentifier
      }), let profile = profileProvider(description)
    else { return }
    beginSession(identifier)
    let lease = try await acquire(
      identifier,
      target: profile,
      isEligible: isEligible,
      factory: factory
    )
    await lease?.release()
  }

  /// Starts a new physical session for a controller that `stop` ended, as when the same
  /// controller starts again after system sleep. Work from the ended session stays invalid.
  func beginSession(_ identifier: DeviceIdentifier) {
    guard !closed, entries[identifier]?.physicalSessionActive == false else { return }
    entries[identifier]?.physicalSessionActive = true
    entries[identifier]?.sessionGeneration &+= 1
    entries[identifier]?.publicationGeneration &+= 1
  }

  func activate(
    identifiers: [DeviceIdentifier],
    descriptions: [ApplicationServiceDeviceDescription],
    isEligible: @escaping Eligibility,
    profileProvider: @escaping ProfileProvider,
    factory: @escaping (DeviceIdentifier) -> Factory
  ) async throws {
    guard !closed, entries.isEmpty else {
      throw UserSpaceOutputDispatcher.CreationError.createFailed
    }
    var seen = Set<DeviceIdentifier>()
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
  func leaseForNeutralization(_ controller: DeviceIdentifier) async -> AutomaticBackendLease? {
    if closed {
      await close()
      return nil
    }
    if let lease = entries[controller]?.installed?.acquire() { return lease }
    _ = await entries[controller]?.retiring?.retireAndWait()
    return nil
  }

  func leaseForDispatch(
    controller: DeviceIdentifier,
    profile: VirtualHIDProfileID,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory
  ) async -> AutomaticBackendLease? {
    try? await acquire(controller, target: profile, isEligible: isEligible, factory: factory)
  }

  /// Replaces the controller's live backend with one for `target`, keeping the live backend
  /// publishing until the replacement has activated. A live backend that already publishes
  /// `target` is left unchanged unless `rebuildsLiveTarget` is set, as when only the persona
  /// identity changed, which is fixed when the device is created. Without a live backend, as
  /// during suppression or recovery, the publication context adopts `target`, so the next
  /// installation publishes it.
  ///
  /// - Throws: The build or activation failure, or `CancellationError` when the controller
  ///   stopped, the coordinator closed, or the replacement could not be installed.
  func retarget(
    _ controller: DeviceIdentifier,
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

  func acquire(
    _ controller: DeviceIdentifier,
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

  private func validate(_ request: Request) throws {
    try Task.checkCancellation()
    guard !closed, !suppressed, let entry = entries[request.controller],
      entry.physicalSessionActive, entry.sessionGeneration == request.sessionGeneration,
      entry.publicationGeneration == request.publicationGeneration,
      entry.pending?.request.token == request.token
    else { throw CancellationError() }
  }

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
  private func neutralize(_ slot: AutomaticBackendSlot, controller: DeviceIdentifier) async {
    guard let lease = slot.acquire() else { return }
    if let sink = lease.backend as? any RemappingGamepadSink {
      try? await sink.send(RemappingGamepadState.neutral, for: controller)
    }
    await lease.release()
  }

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

  private func restore(
    target: VirtualHIDProfileID,
    request: Request,
    factory: @escaping Factory
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
