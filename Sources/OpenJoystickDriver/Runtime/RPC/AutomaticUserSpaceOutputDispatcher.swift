import AppKit
import Foundation
import OpenJoystickDriverKit

final class AutomaticBackendSlot: @unchecked Sendable {
  let backend: any CompatibilityUserSpaceOutputDispatching
  private let lock = NSLock()
  private var leases = 0
  private var retired = false
  private var closed = false
  private var closeCompleted = false
  private var retirementWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []
  init(_ backend: any CompatibilityUserSpaceOutputDispatching) { self.backend = backend }
  func acquire() -> AutomaticBackendLease? {
    lock.withLock {
      guard !retired && !closed else { return nil }
      leases += 1
      return AutomaticBackendLease(self)
    }
  }
  func retire() async { await retireAndWait() }
  func retireAndWait() async {
    let shouldClose = lock.withLock {
      retired = true
      return leases == 0
    }
    if shouldClose { await closeOnce() } else { await waitForCloseCompletion() }
  }
  func release() async {
    let shouldClose = lock.withLock { () -> Bool in
      leases -= 1
      return retired && leases == 0 && !closed
    }
    if shouldClose { await closeOnce() }
  }
  func closeOnce() async {
    let owner = lock.withLock { () -> Int in
      if closeCompleted { return 0 }
      if !closed {
        closed = true
        return 1
      }
      return 2
    }
    if owner == 1 {
      await backend.close()
      let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
        closeCompleted = true
        let result = retirementWaiters + closeWaiters
        retirementWaiters.removeAll()
        closeWaiters.removeAll()
        return result
      }
      waiters.forEach { $0.resume() }
    } else if owner == 2 {
      await waitForCloseCompletion()
    }
  }
  private func waitForCloseCompletion() async {
    await withCheckedContinuation { continuation in
      let complete = lock.withLock { () -> Bool in
        if closeCompleted { return true }
        closeWaiters.append(continuation)
        return false
      }
      if complete { continuation.resume() }
    }
  }
}

final class AutomaticBackendLease: @unchecked Sendable {
  private let slot: AutomaticBackendSlot
  private let lock = NSLock()
  private var released = false
  init(_ slot: AutomaticBackendSlot) { self.slot = slot }
  var backend: any CompatibilityUserSpaceOutputDispatching { slot.backend }
  func release() async {
    let shouldRelease = lock.withLock {
      guard !released else { return false }
      released = true
      return true
    }
    if shouldRelease { await slot.release() }
  }
}

private actor AutomaticDispatcherCoordinator {
  struct Pending {
    let controller: DeviceIdentifier
    let token: UUID
    let controllerGeneration: UInt64
    let foregroundGeneration: UInt64
    let consumer: CompatibilityConsumerFamily
    let identity: CompatibilityIdentity
    let task: Task<AutomaticBackendSlot, Error>
  }
  struct Entry {
    var generation: UInt64 = 0
    var alive = true
    var consumer: CompatibilityConsumerFamily?
    var identity: CompatibilityIdentity?
    var installed: AutomaticBackendSlot?
    var pending: Pending?
    var pendingTasks: [UUID: Pending] = [:]
    var installedToken: UUID?
  }
  var closed = false
  var closeFinished = false
  var closeWaiters: [CheckedContinuation<Void, Never>] = []
  var foregroundGeneration: UInt64 = 0
  var currentConsumer: CompatibilityConsumerFamily = .unknown
  var entries: [DeviceIdentifier: Entry] = [:]

  func activateOne(
    identifier: DeviceIdentifier,
    descriptions: [ApplicationServiceDeviceDescription],
    consumer: CompatibilityConsumerFamily,
    isEligible: @escaping @Sendable (DeviceIdentifier, CompatibilityIdentity) async -> Bool,
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
      CompatibilityIdentity,
    factory:
      @escaping @Sendable (CompatibilityIdentity) throws ->
      any CompatibilityUserSpaceOutputDispatching
  ) async throws {
    guard !closed else { throw UserSpaceOutputDispatcher.CreationError.createFailed }
    let description = descriptions.first { $0.runtimeIdentifier == identifier.runtimeIdentifier }
    let identity = description.map { identityProvider($0, consumer) } ?? .genericHID
    guard await isEligible(identifier, identity) else { return }
    let slot = AutomaticBackendSlot(try factory(identity))
    do {
      try await slot.backend.activate(for: [identifier])
      guard !closed else { throw CancellationError() }
      await slot.backend.setOutputSuppressed(suppressedOutput)
      var entry = Entry()
      entry.consumer = consumer
      entry.identity = identity
      entry.installed = slot
      entries[identifier] = entry
      currentConsumer = consumer
    } catch {
      await slot.closeOnce()
      throw error
    }
  }

  func activate(
    identifiers: [DeviceIdentifier],
    descriptions: [ApplicationServiceDeviceDescription],
    consumer: CompatibilityConsumerFamily,
    isEligible: @escaping @Sendable (DeviceIdentifier, CompatibilityIdentity) async -> Bool,
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
      CompatibilityIdentity,
    factory:
      @escaping @Sendable (CompatibilityIdentity) throws ->
      any CompatibilityUserSpaceOutputDispatching
  ) async throws {
    guard !closed, entries.isEmpty else {
      throw UserSpaceOutputDispatcher.CreationError.createFailed
    }

    var seen = Set<DeviceIdentifier>()
    let identifiers = identifiers.filter { seen.insert($0).inserted }
    do {
      for identifier in identifiers {
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
      let installed = entries.values.compactMap(\.installed)
      entries.removeAll()
      for slot in installed { await slot.closeOnce() }
      throw error
    }
  }

  func leaseForDispatch(
    controller: DeviceIdentifier,
    consumer: CompatibilityConsumerFamily,
    identity: CompatibilityIdentity,
    isEligible: @escaping @Sendable (DeviceIdentifier, CompatibilityIdentity) async -> Bool,
    factory:
      @escaping @Sendable (CompatibilityIdentity) throws ->
      any CompatibilityUserSpaceOutputDispatching
  ) async -> AutomaticBackendLease? {
    if closed { return nil }
    guard await isEligible(controller, identity) else { return nil }
    guard currentConsumer == consumer || currentConsumer == .unknown else { return nil }
    if currentConsumer != consumer {
      currentConsumer = consumer
      foregroundGeneration &+= 1
      for key in entries.keys {
        entries[key]?.pendingTasks.values.forEach { $0.task.cancel() }
        entries[key]?.pending = nil
      }
    }
    var entry = entries[controller] ?? Entry()
    entries[controller] = entry
    if let installed = entry.installed, entry.identity == identity, let lease = installed.acquire()
    {
      entry.consumer = consumer
      entries[controller] = entry
      return lease
    }
    let generation = entry.generation
    let pending: Pending
    if let old = entry.pending, old.controllerGeneration == generation,
      old.foregroundGeneration == foregroundGeneration,
      old.consumer == consumer && old.identity == identity
    {
      pending = old
    } else {
      entry.pending?.task.cancel()
      let token = UUID()
      let fg = foregroundGeneration
      let task = Task { () throws -> AutomaticBackendSlot in
        try Task.checkCancellation()
        let slot = AutomaticBackendSlot(try factory(identity))
        do { try Task.checkCancellation() } catch {
          await slot.closeOnce()
          throw error
        }
        return slot
      }
      pending = Pending(
        controller: controller,
        token: token,
        controllerGeneration: generation,
        foregroundGeneration: fg,
        consumer: consumer,
        identity: identity,
        task: task
      )
      entry.pending = pending
      entry.pendingTasks[token] = pending
      entries[controller] = entry
    }
    do {
      let candidate = try await pending.task.value
      guard var current = entries[controller], !closed, current.alive,
        current.generation == pending.controllerGeneration,
        foregroundGeneration == pending.foregroundGeneration, currentConsumer == pending.consumer,
        current.pending?.token == pending.token || current.installedToken == pending.token
      else {
        if var finished = entries[controller] {
          finished.pendingTasks[pending.token] = nil
          if finished.pending?.token == pending.token { finished.pending = nil }
          entries[controller] = finished
        }
        await candidate.closeOnce()
        return nil
      }
      current.pendingTasks[pending.token] = nil
      if current.pending?.token == pending.token { current.pending = nil }
      if current.installedToken == pending.token, current.installed === candidate,
        let lease = candidate.acquire()
      {
        return lease
      }
      if let installed = current.installed, current.identity == identity,
        let lease = installed.acquire()
      {
        if installed === candidate { return lease }
        await candidate.closeOnce()
        current.consumer = consumer
        entries[controller] = current
        return lease
      }
      if let old = current.installed { await old.retireAndWait() }
      current.installed = candidate
      current.consumer = consumer
      current.identity = identity
      current.installedToken = pending.token
      await candidate.backend.setOutputSuppressed(suppressedOutput)
      entries[controller] = current
      return candidate.acquire()
    } catch {
      if var finished = entries[controller] {
        finished.pendingTasks[pending.token] = nil
        if finished.pending?.token == pending.token { finished.pending = nil }
        entries[controller] = finished
      }
      return nil
    }
  }

  var suppressedOutput = false

  func setConsumer(_ consumer: CompatibilityConsumerFamily) {
    guard !closed else { return }
    guard currentConsumer != consumer else { return }
    currentConsumer = consumer
    foregroundGeneration &+= 1
    for key in entries.keys {
      entries[key]?.pendingTasks.values.forEach { $0.task.cancel() }
      entries[key]?.pending = nil
    }
  }

  func canAdoptConsumer(
    _ consumer: CompatibilityConsumerFamily,
    descriptions: [ApplicationServiceDeviceDescription],
    isEligible: @escaping @Sendable (DeviceIdentifier, CompatibilityIdentity) async -> Bool,
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
      CompatibilityIdentity
  ) async -> Bool {
    for (controller, entry) in entries where entry.alive && entry.installed != nil {
      guard
        let description = descriptions.first(where: {
          $0.runtimeIdentifier == controller.runtimeIdentifier
        })
      else { return false }
      let identity = identityProvider(description, consumer)
      guard identity == entry.identity, await isEligible(controller, identity) else { return false }
    }
    return true
  }

  func adoptConsumer(_ consumer: CompatibilityConsumerFamily) {
    setConsumer(consumer)
    for key in entries.keys { entries[key]?.consumer = consumer }
  }

  func setSuppressed(_ value: Bool) async {
    suppressedOutput = value
    for entry in entries.values {
      if let backend = entry.installed?.backend { await backend.setOutputSuppressed(value) }
    }
  }

  func stop(_ controller: DeviceIdentifier) async {
    guard var entry = entries[controller] else { return }
    entry.generation &+= 1
    entry.alive = false
    let pending = Array(entry.pendingTasks.values)
    pending.forEach { $0.task.cancel() }
    entry.pending = nil
    let installed = entry.installed
    entry.installed = nil
    entry.installedToken = nil
    entry.identity = nil
    entries[controller] = entry
    if let installed { await installed.retireAndWait() }
    for item in pending {
      if let slot = try? await item.task.value { await slot.closeOnce() }
      guard var current = entries[controller] else { continue }
      current.pendingTasks[item.token] = nil
      entries[controller] = current
    }
  }

  func close() async {
    if closed {
      if closeFinished { return }
      await withCheckedContinuation { continuation in closeWaiters.append(continuation) }
      return
    }
    closed = true
    foregroundGeneration &+= 1
    let pending = entries.values.flatMap { $0.pendingTasks.values }
    let installed = entries.values.compactMap { $0.installed }
    for key in entries.keys {
      entries[key]?.pendingTasks.values.forEach { $0.task.cancel() }
      entries[key]?.pending = nil
      entries[key]?.installed = nil
      entries[key]?.installedToken = nil
      entries[key]?.identity = nil
    }
    for slot in installed { await slot.retireAndWait() }
    for item in pending {
      if let slot = try? await item.task.value { await slot.closeOnce() }
      guard var current = entries[item.controller] else { continue }
      current.pendingTasks[item.token] = nil
      entries[item.controller] = current
    }
    closeFinished = true
    let waiters = closeWaiters
    closeWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}

final class AutomaticUserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, ControllerLifecycleListener, @unchecked Sendable
{
  private let deviceManager: DeviceManager
  private let ownershipProvider:
    @Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation
  private let descriptionsProvider: @Sendable () async -> [ApplicationServiceDeviceDescription]
  private let consumerProvider: @Sendable () -> CompatibilityConsumerFamily
  private let identityProvider:
    @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
      CompatibilityIdentity
  private let builder:
    @Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching
  private let transitionRequester: @Sendable () -> Void
  private let coordinator = AutomaticDispatcherCoordinator()
  private var observation: NSObjectProtocol?
  private var observationTask: Task<Void, Never>?
  init(
    deviceManager: DeviceManager,
    ownershipProvider: (@Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation)? =
      nil,
    consumerProvider: @escaping @Sendable () -> CompatibilityConsumerFamily,
    builder:
      @escaping @Sendable (CompatibilityIdentity) throws ->
      any CompatibilityUserSpaceOutputDispatching,
    observeConsumerChanges: Bool = true,
    descriptionsProvider: (@Sendable () async -> [ApplicationServiceDeviceDescription])? = nil,
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription, CompatibilityConsumerFamily) ->
      CompatibilityIdentity = { description, consumer in
        AutomaticCompatibilityResolver.resolve(for: description, consumer: consumer).identity
      },
    transitionRequester: @escaping @Sendable () -> Void = {}
  ) {
    self.deviceManager = deviceManager
    self.ownershipProvider =
      ownershipProvider ?? { identifier in await deviceManager.ownershipObservation(for: identifier)
      }
    self.descriptionsProvider =
      descriptionsProvider ?? { await deviceManager.connectedDeviceDescriptions() }
    self.consumerProvider = consumerProvider
    self.identityProvider = identityProvider
    self.builder = builder
    self.transitionRequester = transitionRequester
    if observeConsumerChanges {
      observationTask = Task { [weak self] in
        guard let self else { return }
        for await _ in CompatibilityConsumerRouting.changes() {
          await self.refreshForCurrentConsumer()
        }
      }
    }
  }
  var suppressOutput: Bool = false
  func activate(controller identifier: DeviceIdentifier) async throws {
    try await coordinator.activateOne(
      identifier: identifier,
      descriptions: await descriptionsProvider(),
      consumer: consumerProvider(),
      isEligible: { [weak self] identifier, identity in
        await self?.isEligible(identifier, identity: identity) ?? false
      },
      identityProvider: identityProvider,
      factory: builder
    )
  }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    try await coordinator.activate(
      identifiers: identifiers,
      descriptions: await descriptionsProvider(),
      consumer: consumerProvider(),
      isEligible: { [weak self] identifier, identity in
        await self?.isEligible(identifier, identity: identity) ?? false
      },
      identityProvider: identityProvider,
      factory: builder
    )
  }

  func setOutputSuppressed(_ suppressed: Bool) async {
    suppressOutput = suppressed
    await coordinator.setSuppressed(suppressed)
  }
  var status: String { "automatic" }
  var lastRumbleStatus: String { "none" }
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    await coordinator.setSuppressed(suppressOutput)
    let description = await descriptionsProvider().first {
      $0.runtimeIdentifier == identifier.runtimeIdentifier
    }
    let consumer = consumerProvider()
    let identity = description.map { identityProvider($0, consumer) } ?? .genericHID
    guard
      let lease = await coordinator.leaseForDispatch(
        controller: identifier,
        consumer: consumer,
        identity: identity,
        isEligible: { [weak self] identifier, identity in
          await self?.isEligible(identifier, identity: identity) ?? false
        },
        factory: builder
      )
    else { return }
    await lease.backend.dispatch(events: events, from: identifier)
    await lease.release()
  }
  func controllerDidStop(_ identifier: DeviceIdentifier) async {
    await coordinator.stop(identifier)
  }
  func refreshForCurrentConsumer() async {
    let consumer = consumerProvider()
    let descriptions = await descriptionsProvider()
    if await coordinator.canAdoptConsumer(
      consumer,
      descriptions: descriptions,
      isEligible: { [weak self] identifier, identity in
        await self?.isEligible(identifier, identity: identity) ?? false
      },
      identityProvider: identityProvider
    ) {
      await coordinator.adoptConsumer(consumer)
    } else {
      transitionRequester()
    }
  }

  private func isEligible(_ identifier: DeviceIdentifier, identity: CompatibilityIdentity) async
    -> Bool
  {
    guard identity != .automatic else { return false }
    guard
      let description = await descriptionsProvider().first(where: {
        $0.runtimeIdentifier == identifier.runtimeIdentifier
      })
    else { return false }
    let ownership = await ownershipProvider(identifier)
    let profileAvailable = CompatibilityProfileAvailabilityPolicy.isAvailable(
      identity,
      for: AutomaticCompatibilityResolver.resolve(for: description).subfamily
    )
    return ControllerExposureDecision.decide(
      ownership: ownership,
      intent: .automatic(resolvedIdentity: identity),
      profileAvailable: profileAvailable
    ).eligibility == .eligible
  }
  func close() async {
    observation.map { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observationTask?.cancel()
    if let observationTask { await observationTask.value }
    observationTask = nil
    await coordinator.close()
  }
}
