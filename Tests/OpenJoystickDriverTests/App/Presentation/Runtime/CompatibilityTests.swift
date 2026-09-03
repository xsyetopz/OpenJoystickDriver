import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

private final class AutomaticBackendProbe: CompatibilityUserSpaceOutputDispatching,
  ControllerLifecycleListener, @unchecked Sendable
{
  struct ActivationFailure: Error, Sendable {}

  let failsActivation: Bool
  private(set) var closed = false
  private(set) var activations: [[DeviceIdentifier]] = []
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }
  init(failsActivation: Bool = false) { self.failsActivation = failsActivation }
  func activate(for identifiers: [DeviceIdentifier]) throws {
    activations.append(identifiers)
    if failsActivation { throw ActivationFailure() }
  }
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {}
  func controllerDidStop(_ identifier: DeviceIdentifier) {}
  func close() { closed = true }
}

private final class AutomaticConsumerBox: @unchecked Sendable {
  private let lock = NSLock()
  var value = CompatibilityConsumerFamily.sdlHIDAPI
  var created: [AutomaticBackendProbe] = []
  private var transitionRequests = 0

  func requestTransition() { lock.withLock { transitionRequests += 1 } }
  func transitionRequestCount() -> Int { lock.withLock { transitionRequests } }
}

private final class ConcurrentBackendProbe: CompatibilityUserSpaceOutputDispatching,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var dispatchCount = 0
  private var closeCount = 0
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }
  func activate(for identifiers: [DeviceIdentifier]) throws {}
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    lock.withLock { dispatchCount += 1 }
  }
  func controllerDidStop(_ identifier: DeviceIdentifier) {}
  func close() { lock.withLock { closeCount += 1 } }
  func counts() -> (Int, Int) { lock.withLock { (dispatchCount, closeCount) } }
}

private final class ConcurrentFactoryProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let enteredSignal = DispatchSemaphore(value: 0)
  private(set) var created = 0
  private(set) var entered = 0
  private(set) var backends: [ConcurrentBackendProbe] = []
  var gate: DispatchSemaphore?
  func make() -> ConcurrentBackendProbe {
    lock.withLock { entered += 1 }
    enteredSignal.signal()
    gate?.wait()
    return lock.withLock {
      created += 1
      let backend = ConcurrentBackendProbe()
      backends.append(backend)
      return backend
    }
  }
  func snapshot() -> (Int, Int, [ConcurrentBackendProbe]) {
    lock.withLock { (created, entered, backends) }
  }
  func waitForEntered() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        self.enteredSignal.wait()
        continuation.resume()
      }
    }
  }
}

@Suite(.serialized) struct CompatibilityTests {
  private func provider(_ values: [ApplicationServiceDeviceDescription])
    -> @Sendable () async -> [ApplicationServiceDeviceDescription]
  { { values } }

  private func description(_ id: DeviceIdentifier) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "probe",
      vendorID: id.vendorID,
      productID: id.productID,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne,
      runtimeIdentifier: id.runtimeIdentifier
    )
  }

  @Test func automaticConsumerChangesWithSameEffectiveIdentityDoNotRebuild() async {
    let identifier = DeviceIdentifier(vendorID: 0x057E, productID: 0x2009)
    let probe = ConcurrentFactoryProbe()
    let box = AutomaticConsumerBox()
    let description = ApplicationServiceDeviceDescription(
      name: "Switch",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      parser: "SwitchPro",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .switchPro,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
    let descriptionsProvider: @Sendable () -> [ApplicationServiceDeviceDescription] = {
      [description]
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { box.value },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: descriptionsProvider
    )

    await dispatcher.dispatch(events: [], from: identifier)
    box.value = .appleGameController
    await dispatcher.refreshForCurrentConsumer()

    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2.first?.counts().1 == 0)
    await dispatcher.close()
  }

  @Test func automaticActivationBuildsOneCoherentChildPerController() async throws {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4)
    ]
    let created = AutomaticConsumerBox()
    let descriptions = identifiers.map { description($0) }
    let descriptionsProvider: @Sendable () -> [ApplicationServiceDeviceDescription] = {
      descriptions
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in
        let backend = AutomaticBackendProbe()
        created.created.append(backend)
        return backend
      },
      observeConsumerChanges: false,
      descriptionsProvider: descriptionsProvider
    )

    try await dispatcher.activate(for: identifiers)
    #expect(created.created.count == identifiers.count)
    #expect(created.created.map(\.activations) == identifiers.map { [[$0]] })
    await dispatcher.dispatch(events: [], from: identifiers[0])
    await dispatcher.close()
    #expect(created.created.allSatisfy { $0.closed })
  }

  @Test func automaticActivationFailureClosesTheEntireChildSet() async {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4)
    ]
    let created = AutomaticConsumerBox()
    let descriptions = identifiers.map { description($0) }
    let descriptionsProvider: @Sendable () -> [ApplicationServiceDeviceDescription] = {
      descriptions
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in
        let backend = AutomaticBackendProbe(failsActivation: created.created.count == 1)
        created.created.append(backend)
        return backend
      },
      observeConsumerChanges: false,
      descriptionsProvider: descriptionsProvider
    )

    do {
      try await dispatcher.activate(for: identifiers)
      Issue.record("Activation unexpectedly succeeded")
    } catch {}
    #expect(created.created.count == identifiers.count)
    #expect(created.created.allSatisfy { $0.closed })
    await dispatcher.close()
  }

  @Test func automaticEffectiveIdentityChangeDelegatesWithoutOverlappingChildren() async throws {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4)
    ]
    let created = AutomaticConsumerBox()
    let box = AutomaticConsumerBox()
    let descriptions = identifiers.map { description($0) }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { box.value },
      builder: { _ in
        let backend = AutomaticBackendProbe()
        created.created.append(backend)
        return backend
      },
      observeConsumerChanges: false,
      descriptionsProvider: { descriptions },
      identityProvider: { _, consumer in consumer == .sdlHIDAPI ? .genericHID : .appleGameController
      },
      transitionRequester: { box.requestTransition() }
    )

    try await dispatcher.activate(for: identifiers)
    box.value = .appleGameController
    await dispatcher.refreshForCurrentConsumer()

    #expect(box.transitionRequestCount() == 1)
    #expect(created.created.count == 2)
    #expect(created.created.allSatisfy { !$0.closed })
    await dispatcher.close()
  }

  @Test func repeatedChangedIdentityRefreshRequestsTheOwningTransition() async throws {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4)
    ]
    let created = AutomaticConsumerBox()
    let box = AutomaticConsumerBox()
    let descriptions = identifiers.map { description($0) }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { box.value },
      builder: { _ in
        let backend = AutomaticBackendProbe()
        created.created.append(backend)
        return backend
      },
      observeConsumerChanges: false,
      descriptionsProvider: { descriptions },
      identityProvider: { _, consumer in consumer == .sdlHIDAPI ? .genericHID : .appleGameController
      },
      transitionRequester: { box.requestTransition() }
    )

    try await dispatcher.activate(for: identifiers)
    let original = created.created
    box.value = .appleGameController
    await dispatcher.refreshForCurrentConsumer()
    await dispatcher.refreshForCurrentConsumer()

    #expect(box.transitionRequestCount() == 2)
    #expect(created.created.count == 2)
    #expect(original.allSatisfy { !$0.closed })
    await dispatcher.close()
  }

  @Test func concurrentFirstDispatchCoalescesAndKeepsBothEvents() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    let first = Task { await dispatcher.dispatch(events: [], from: id) }
    await probe.waitForEntered()
    let second = Task { await dispatcher.dispatch(events: [], from: id) }
    #expect(probe.snapshot().0 == 0)
    probe.gate?.signal()
    await first.value
    await second.value
    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2[0].counts().0 == 2)
    #expect(probe.snapshot().2[0].counts().1 == 0)
    await dispatcher.close()
    #expect(probe.snapshot().2[0].counts().1 == 1)
  }

  @Test func differentControllersBuildIndependently() async {
    let first = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let second = DeviceIdentifier(vendorID: 0x3537, productID: 0x1011)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(first), description(second)])
    )
    let firstTask = Task { await dispatcher.dispatch(events: [], from: first) }
    let secondTask = Task { await dispatcher.dispatch(events: [], from: second) }
    await probe.waitForEntered()
    await probe.waitForEntered()
    #expect(probe.snapshot().1 == 2)
    probe.gate?.signal()
    probe.gate?.signal()
    await firstTask.value
    await secondTask.value
    #expect(probe.snapshot().0 == 2)
    await dispatcher.close()
  }

  @Test func stopDuringBuildDoesNotResurrect() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    let task = Task { await dispatcher.dispatch(events: [], from: id) }
    await probe.waitForEntered()
    let stop = Task { await dispatcher.controllerDidStop(id) }
    #expect(probe.snapshot().2.isEmpty)
    probe.gate?.signal()
    await stop.value
    await task.value
    let counts = probe.snapshot().2.first?.counts()
    #expect(counts?.0 == 0)
    #expect(counts?.1 == 1)
    await dispatcher.close()
  }

  @Test func closeDuringBuildClosesExactlyOnce() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    let task = Task { await dispatcher.dispatch(events: [], from: id) }
    await probe.waitForEntered()
    let close = Task { await dispatcher.close() }
    #expect(probe.snapshot().2.isEmpty)
    probe.gate?.signal()
    await close.value
    await task.value
    #expect(probe.snapshot().2.first?.counts().1 == 1)
  }

  @Test func retiredLeaseClosesAfterReleaseOnlyOnce() async {
    let backend = ConcurrentBackendProbe()
    let slot = AutomaticBackendSlot(backend)
    let lease = slot.acquire()
    let retirement = Task { await slot.retireAndWait() }
    #expect(backend.counts().1 == 0)
    await lease?.release()
    await retirement.value
    #expect(backend.counts().1 == 1)
  }

  @Test func suppressionForwardsToNewAndReusedBackends() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.setOutputSuppressed(true)
    await dispatcher.dispatch(events: [], from: id)
    #expect(probe.snapshot().2.first?.suppressOutput == true)
    await dispatcher.setOutputSuppressed(false)
    #expect(probe.snapshot().2.first?.suppressOutput == false)
    await dispatcher.close()
  }

  @Test func repeatedForegroundRefreshesKeepLatestBackend() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let box = AutomaticConsumerBox()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { box.value },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.dispatch(events: [], from: id)
    box.value = .appleGameController
    for _ in 0..<3 { await dispatcher.refreshForCurrentConsumer() }
    #expect(probe.snapshot().0 == 1)
    await dispatcher.close()
  }

  @Test func unchangedForegroundRefreshPreservesVirtualDevice() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.dispatch(events: [], from: id)
    for _ in 0..<3 { await dispatcher.refreshForCurrentConsumer() }

    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2[0].counts().1 == 0)
    await dispatcher.close()
  }

  @Test func consumerChangeDoesNotDropCurrentDispatch() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let box = AutomaticConsumerBox()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { box.value },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.dispatch(events: [], from: id)
    box.value = .appleGameController
    await dispatcher.refreshForCurrentConsumer()
    await dispatcher.dispatch(events: [], from: id)
    #expect(probe.snapshot().2.map { $0.counts().0 } == [2])
    await dispatcher.close()
  }

  @Test func unrelatedControllerStopLeavesOtherControllerUsable() async {
    let first = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let second = DeviceIdentifier(vendorID: 0x3537, productID: 0x1011)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: { .sdlHIDAPI },
      builder: { _ in probe.make() },
      observeConsumerChanges: false,
      descriptionsProvider: provider([description(first), description(second)])
    )
    await dispatcher.dispatch(events: [], from: second)
    await dispatcher.controllerDidStop(first)
    await dispatcher.dispatch(events: [], from: second)
    #expect(probe.snapshot().2.first?.counts().0 == 2)
    await dispatcher.close()
  }

  @Test func automaticDispatcherRefreshesOnConsumerChangeWithoutInput() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let description = ApplicationServiceDeviceDescription(
      name: "GameSir",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
    let box = AutomaticConsumerBox()
    let builder:
      @Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching = {
        _ in
        let backend = AutomaticBackendProbe()
        box.created.append(backend)
        return backend
      }
    let consumerProvider: @Sendable () -> CompatibilityConsumerFamily = { box.value }
    let descriptionsProvider: @Sendable () async -> [ApplicationServiceDeviceDescription] = {
      [description]
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: manager,
      ownershipProvider: { _ in .exclusiveRawUSB },
      consumerProvider: consumerProvider,
      builder: builder,
      observeConsumerChanges: false,
      descriptionsProvider: descriptionsProvider
    )
    await dispatcher.dispatch(events: [], from: identifier)
    box.value = .appleGameController
    await dispatcher.refreshForCurrentConsumer()
    box.value = .unknown
    await dispatcher.refreshForCurrentConsumer()
    #expect(box.created.count == 1)
    await dispatcher.controllerDidStop(identifier)
    #expect(box.created.last?.closed == true)
    await dispatcher.close()
  }

  @Test func coalescingStressRunsTwentyFiveExplicitIterations() async {
    for _ in 0..<25 {
      let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
      let probe = ConcurrentFactoryProbe()
      let dispatcher = AutomaticUserSpaceOutputDispatcher(
        deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
        ownershipProvider: { _ in .exclusiveRawUSB },
        consumerProvider: { .sdlHIDAPI },
        builder: { _ in probe.make() },
        observeConsumerChanges: false,
        descriptionsProvider: provider([description(id)])
      )
      await dispatcher.dispatch(events: [], from: id)
      #expect(probe.snapshot().0 == 1)
      await dispatcher.close()
      #expect(probe.snapshot().2[0].counts().1 == 1)
    }
  }

  @Test func rejectedCompatibilityIdentityDoesNotPublishRequestedValue() async {
    let gateway = GatewayStub(setIdentityResult: false)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .error = state else {
      Issue.record("Expected a rejected identity to produce an error")
      return
    }
    #expect(await MainActor.run { viewModel.compatibilityError } != nil)
    #expect(await gateway.selectedIdentity == .sdl2_3)
  }

  @Test func resettingCompatibilityIdentityUsesTheScopedMutation() async {
    let gateway = GatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.resetCompatibilityIdentity()

    #expect(await gateway.selectedIdentity == .automatic)
    #expect(await gateway.setIdentityCallCount == 1)
  }

  @Test func compatibilitySuccessDoesNotInheritAnUnrelatedRuntimeError() async {
    let gateway = GatewayStub(statusShouldFail: true)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let state = await MainActor.run { (viewModel.compatibilityState, viewModel.compatibilityError) }
    guard case .available = state.0 else {
      Issue.record("Expected compatibility identity loading to succeed")
      return
    }
    #expect(state.1 == nil)
    #expect(await MainActor.run { viewModel.lastError } != nil)
  }

  @Test func newerCompatibilitySelectionWinsOverAnOlderIdentityRead() async {
    let gateway = GatewayStub(compatibilityReadDelayNanoseconds: 100_000_000)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let read = Task { @MainActor in await viewModel.loadCompatibilityIdentity() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.setCompatibilityIdentity(.appleGameController)
    await read.value

    let state = await MainActor.run { viewModel.compatibilityState }
    guard case .available(let identity) = state else {
      Issue.record("Expected the newer compatibility selection to remain authoritative")
      return
    }
    #expect(identity == .appleGameController)
  }

  @Test func compatibilitySelectionUpdatesTheStatusSummary() async {
    let gateway = GatewayStub()
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    await viewModel.setCompatibilityIdentity(.appleGameController)

    let state = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = state else {
      Issue.record("Expected the status summary to remain available")
      return
    }
    #expect(status.compatibilityIdentity == .appleGameController)
    #expect(status.compatibilityLabel == "Apple GameController")
  }

  @Test func rpcRejectsLegacyIdentityWithoutChangingRuntimeOrPersistence() async {
    let defaults = UserDefaults.standard
    let key = ApplicationServiceServer.compatibilityIdentityDefaultsKey
    let priorRawValue = defaults.object(forKey: key)
    defaults.set(CompatibilityIdentity.appleGameController.rawValue, forKey: key)
    defer {
      if let priorRawValue {
        defaults.set(priorRawValue, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }

    let permissionManager = PermissionManager()
    let dispatcher = CompatibilityOutputDispatcher()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess)
    )
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: remappingEngine,
      compatibility: dispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let deviceManager = DeviceManager(dispatcher: remappingRouter)
    let server = ApplicationServiceServer(
      deviceManager: deviceManager,
      permissionManager: permissionManager,
      dispatcher: dispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess
    )
    let priorRuntimeIdentity = server.compatibilityIdentity
    let priorRuntimeEnabled = server.userSpaceEnabled
    let priorRuntimeStatus = server.currentUserSpaceStatus()

    let accepted = await withCheckedContinuation { continuation in
      server.setCompatibilityIdentity("xone-hid") { result in continuation.resume(returning: result)
      }
    }

    #expect(accepted == false)
    #expect(server.compatibilityIdentity == priorRuntimeIdentity)
    #expect(server.userSpaceEnabled == priorRuntimeEnabled)
    #expect(server.currentUserSpaceStatus() == priorRuntimeStatus)
    #expect(defaults.string(forKey: key) == CompatibilityIdentity.appleGameController.rawValue)
  }

  @Test func rpcAcceptsCurrentIdentityWithoutReplacingTheLiveBackend() async {
    let permissionManager = PermissionManager()
    let compatibilityDispatcher = CompatibilityOutputDispatcher()
    let profileLibrary = RemappingProfileLibrary()
    let postEventAccess = CoreGraphicsPostEventAccess()
    let remappingEngine = RemappingEventEngine(
      sink: CoreGraphicsSystemInputSink(access: postEventAccess)
    )
    let remappingRouter = RemappingOutputRouter(
      library: profileLibrary,
      engine: remappingEngine,
      compatibility: compatibilityDispatcher,
      foregroundApplication: WorkspaceRemappingForegroundApplication(),
      postEventAccess: postEventAccess
    )
    let server = ApplicationServiceServer(
      deviceManager: DeviceManager(dispatcher: remappingRouter),
      permissionManager: permissionManager,
      dispatcher: compatibilityDispatcher,
      remappingProfileLibrary: profileLibrary,
      remappingRouter: remappingRouter,
      postEventAccess: postEventAccess
    )
    let backend = AutomaticBackendProbe()
    server.userSpaceLock.withLock {
      server.compatibilityIdentity = .appleGameController
      server.userSpaceDispatcher = backend
      server.userSpaceEnabled = true
      server.compatibilityLiveIdentity = .appleGameController
      compatibilityDispatcher.setBackend(backend)
    }

    let accepted = await withCheckedContinuation { continuation in
      server.setCompatibilityIdentity(CompatibilityIdentity.appleGameController.rawValue) {
        continuation.resume(returning: $0)
      }
    }

    #expect(accepted)
    #expect(server.userSpaceDispatcher === backend)
    #expect(!backend.closed)
    backend.close()
  }
}
