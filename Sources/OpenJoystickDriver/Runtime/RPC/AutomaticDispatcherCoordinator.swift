import Foundation
import OpenJoystickDriverKit

/// Owns installation requests until activation, retirement, and suppression have completed.
actor AutomaticDispatcherCoordinator {
  typealias Eligibility = @Sendable (DeviceIdentifier, CompatibilityIdentity) async -> Bool
  typealias Factory =
    @Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching
  typealias IdentityProvider =
    @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
    CompatibilityIdentity

  struct Request: Sendable {
    let controller: DeviceIdentifier
    let token: UUID
    let generation: UInt64
    let foreground: UInt64
    let consumer: CompatibilityConsumerFamily
    let identity: CompatibilityIdentity
  }

  struct Pending {
    let request: Request
    let task: Task<Void, Error>
  }

  struct Entry {
    var generation: UInt64 = 0
    var alive = true
    var identity: CompatibilityIdentity?
    var installed: AutomaticBackendSlot?
    var installedToken: UUID?
    var retiring: AutomaticBackendSlot?
    var pending: Pending?
    var tasks: [UUID: Pending] = [:]
  }

  private var entries: [DeviceIdentifier: Entry] = [:]
  private var closed = false
  private var closeFinished = false
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []
  private var foreground: UInt64 = 0
  private var consumer: CompatibilityConsumerFamily = .unknown
  private var remappingSuppressed = false
  private var suppressed = false
  private var suppressionRevision: UInt64 = 0

  func activateOne(
    identifier: DeviceIdentifier,
    descriptions: [ApplicationServiceDeviceDescription],
    consumer: CompatibilityConsumerFamily,
    isEligible: @escaping Eligibility,
    identityProvider: @escaping IdentityProvider,
    factory: @escaping Factory
  ) async throws {
    guard !closed else { throw CancellationError() }
    guard
      let description = descriptions.first(where: {
        $0.runtimeIdentifier == identifier.runtimeIdentifier
      })
    else { return }
    if entries[identifier]?.alive == false { entries[identifier]?.alive = true }
    let lease = try await acquire(
      identifier,
      consumer: consumer,
      identity: identityProvider(description, consumer),
      isEligible: isEligible,
      factory: factory
    )
    await lease?.release()
  }

  func activate(
    identifiers: [DeviceIdentifier],
    descriptions: [ApplicationServiceDeviceDescription],
    consumer: CompatibilityConsumerFamily,
    isEligible: @escaping Eligibility,
    identityProvider: @escaping IdentityProvider,
    factory: @escaping Factory
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
          consumer: consumer,
          isEligible: isEligible,
          identityProvider: identityProvider,
          factory: factory
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
    await entries[controller]?.retiring?.retireAndWait()
    return nil
  }

  func leaseForDispatch(
    controller: DeviceIdentifier,
    consumer: CompatibilityConsumerFamily,
    identity: CompatibilityIdentity,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory
  ) async -> AutomaticBackendLease? {
    try? await acquire(
      controller,
      consumer: consumer,
      identity: identity,
      isEligible: isEligible,
      factory: factory
    )
  }

  private func acquire(
    _ controller: DeviceIdentifier,
    consumer requestedConsumer: CompatibilityConsumerFamily,
    identity: CompatibilityIdentity,
    isEligible: @escaping Eligibility,
    factory: @escaping Factory
  ) async throws -> AutomaticBackendLease? {
    guard !closed, consumer == .unknown || consumer == requestedConsumer else { return nil }
    if consumer != requestedConsumer { setConsumer(requestedConsumer) }
    if entries[controller] == nil { entries[controller] = Entry() }
    guard let initial = entries[controller], initial.alive else { return nil }
    let generation = initial.generation
    let currentForeground = foreground
    guard await isEligible(controller, identity) else { return nil }
    guard !closed, foreground == currentForeground, let current = entries[controller],
      current.alive, current.generation == generation
    else { throw CancellationError() }
    if current.identity == identity, let lease = current.installed?.acquire() { return lease }

    let pending: Pending
    if let existing = current.pending, existing.request.identity == identity {
      pending = existing
    } else {
      current.pending?.task.cancel()
      let request = Request(
        controller: controller,
        token: UUID(),
        generation: generation,
        foreground: foreground,
        consumer: requestedConsumer,
        identity: identity
      )
      let predecessors = current.tasks.values.map(\.task)
      // Factories may synchronously block in native creation. Keep them off the coordinator.
      let task = Task.detached { [self] in
        try Task.checkCancellation()
        let candidate = AutomaticBackendSlot(try factory(identity))
        do {
          for predecessor in predecessors { _ = await predecessor.result }
          try await install(candidate, request: request)
        } catch {
          await candidate.retireAndWait()
          throw error
        }
      }
      pending = Pending(request: request, task: task)
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
    guard !closed, foreground == currentForeground, let installed = entries[controller],
      installed.alive, installed.generation == generation, installed.identity == identity,
      installed.installedToken == pending.request.token
    else { throw CancellationError() }
    return installed.installed?.acquire()
  }

  private func validate(_ request: Request) throws {
    try Task.checkCancellation()
    guard !closed, foreground == request.foreground, consumer == request.consumer,
      let entry = entries[request.controller], entry.alive, entry.generation == request.generation,
      entry.pending?.request.token == request.token
    else { throw CancellationError() }
  }

  private func install(_ candidate: AutomaticBackendSlot, request: Request) async throws {
    try validate(request)
    let old = entries[request.controller]?.installed ?? entries[request.controller]?.retiring
    entries[request.controller]?.retiring = old
    entries[request.controller]?.installed = nil
    entries[request.controller]?.installedToken = nil
    entries[request.controller]?.identity = nil
    if let old {
      await old.retireAndWait()
      try validate(request)
      entries[request.controller]?.retiring = nil
    }
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
    entries[request.controller]?.installed = candidate
    entries[request.controller]?.installedToken = request.token
    entries[request.controller]?.identity = request.identity
  }

  private func setConsumer(_ value: CompatibilityConsumerFamily) {
    guard !closed, consumer != value else { return }
    consumer = value
    foreground &+= 1
    for identifier in entries.keys {
      entries[identifier]?.tasks.values.forEach { $0.task.cancel() }
      entries[identifier]?.pending = nil
    }
  }

  func adoptConsumerIfEligible(
    _ value: CompatibilityConsumerFamily,
    descriptions: [ApplicationServiceDeviceDescription],
    isEligible: @escaping Eligibility,
    identityProvider: @escaping IdentityProvider
  ) async -> Bool {
    let generation = foreground
    let snapshot = entries
    for (controller, entry) in snapshot where entry.alive && entry.installed != nil {
      guard
        let description = descriptions.first(where: {
          $0.runtimeIdentifier == controller.runtimeIdentifier
        }), identityProvider(description, value) == entry.identity, let identity = entry.identity,
        await isEligible(controller, identity)
      else { return false }
      guard !closed, foreground == generation, entries[controller]?.generation == entry.generation,
        entries[controller]?.installed === entry.installed
      else { return false }
    }
    guard !closed, foreground == generation, entries.count == snapshot.count else { return false }
    for (controller, entry) in snapshot {
      guard entries[controller]?.generation == entry.generation,
        entries[controller]?.installed === entry.installed,
        entries[controller]?.pending?.request.token == entry.pending?.request.token
      else { return false }
    }
    setConsumer(value)
    return true
  }

  func synchronizeSuppression(_ currentValue: @Sendable () -> Bool) async {
    guard !closed else { return }
    suppressed = currentValue()
    suppressionRevision &+= 1
    let slots = entries.values.compactMap(\.installed)
    for slot in slots {
      guard let lease = slot.acquire() else { continue }
      repeat {
        let revision = suppressionRevision
        await lease.backend.setOutputSuppressed(suppressed)
        if closed || revision == suppressionRevision { break }
      } while true
      await lease.release()
    }
  }

  func synchronizeRemappingSuppression(_ currentValue: @Sendable () -> Bool) async {
    guard !closed else { return }
    remappingSuppressed = currentValue()
    suppressionRevision &+= 1
    let slots = entries.values.compactMap(\.installed)
    for slot in slots {
      guard let lease = slot.acquire() else { continue }
      if let control = lease.backend as? any RemappingGamepadOutputControlling {
        repeat {
          let revision = suppressionRevision
          await control.setRemappingOutputSuppressed(remappingSuppressed)
          if closed || revision == suppressionRevision { break }
        } while true
      }
      await lease.release()
    }
  }

  func stop(_ controller: DeviceIdentifier) async {
    var entry = entries[controller] ?? Entry()
    entry.generation &+= 1
    entry.alive = false
    let installed = entry.installed
    let tasks = entry.tasks.values.map(\.task)
    entry.installed = nil
    entry.identity = nil
    entry.pending = nil
    entries[controller] = entry
    tasks.forEach { $0.cancel() }
    await installed?.retireAndWait()
    for task in tasks { _ = await task.result }
    if entries[controller]?.generation == entry.generation { entries[controller]?.retiring = nil }
  }

  func close() async {
    if closed {
      if !closeFinished { await withCheckedContinuation { closeWaiters.append($0) } }
      return
    }
    closed = true
    foreground &+= 1
    let slots = entries.values.compactMap(\.installed)
    let tasks = entries.values.flatMap { $0.tasks.values.map(\.task) }
    for identifier in entries.keys {
      entries[identifier]?.alive = false
      entries[identifier]?.installed = nil
      entries[identifier]?.pending = nil
    }
    tasks.forEach { $0.cancel() }
    for slot in slots { await slot.retireAndWait() }
    for task in tasks { _ = await task.result }
    entries.removeAll()
    closeFinished = true
    let waiters = closeWaiters
    closeWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
