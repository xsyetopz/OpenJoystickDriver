import Foundation
import OpenJoystickDriverKit

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
  private let stateLock = NSLock()
  private var suppressedOutput = false
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
  var suppressOutput: Bool {
    get { stateLock.withLock { suppressedOutput } }
    set { stateLock.withLock { suppressedOutput = newValue } }
  }
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
    await coordinator.synchronizeSuppression { self.suppressOutput }
  }
  var status: String { "automatic" }
  var lastRumbleStatus: String { "none" }
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    await coordinator.synchronizeSuppression { self.suppressOutput }
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
    if await coordinator.adoptConsumerIfEligible(
      consumer,
      descriptions: descriptions,
      isEligible: { [weak self] identifier, identity in
        await self?.isEligible(identifier, identity: identity) ?? false
      },
      identityProvider: identityProvider
    ) {
      return
    }
    transitionRequester()
  }

  private func isEligible(
    _ identifier: DeviceIdentifier,
    identity: CompatibilityIdentity
  ) async -> Bool {
    guard identity != .automatic else { return false }
    guard
      let description = await descriptionsProvider().first(where: {
        $0.runtimeIdentifier == identifier.runtimeIdentifier
      })
    else { return false }
    let ownership = await ownershipProvider(identifier)
    let profileAvailable = CompatibilityProfileAvailabilityPolicy.decision(
      for: description,
      identity: identity
    ).isAvailable
    return ControllerExposureDecision.decide(
      ownership: ownership,
      intent: .automatic(resolvedIdentity: identity),
      profileAvailable: profileAvailable
    ).eligibility == .eligible
  }
  func close() async {
    let task = stateLock.withLock { observationTask }
    task?.cancel()
    await coordinator.close()
    if let task { await task.value }
  }
}
