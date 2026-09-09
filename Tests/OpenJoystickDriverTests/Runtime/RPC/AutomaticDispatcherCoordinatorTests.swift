import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

private actor InstallationGate {
  private var entered = false
  private var cancelled = false
  private var released = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    entered = true
    entryWaiters.forEach { $0.resume() }
    entryWaiters.removeAll()
    await withTaskCancellationHandler {
      if !released { await withCheckedContinuation { waiters.append($0) } }
    } onCancel: {
      Task { await self.markCancelled() }
    }
  }

  func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
  }

  func waitForCancellation() async {
    if !cancelled { await withCheckedContinuation { cancellationWaiters.append($0) } }
  }

  private func markCancelled() {
    cancelled = true
    cancellationWaiters.forEach { $0.resume() }
    cancellationWaiters.removeAll()
  }

  func release() {
    released = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
  }
}

private final class InstallationBackend: CompatibilityUserSpaceOutputDispatching,
  @unchecked Sendable
{
  enum Stage: Sendable { case activation, suppression, retirement }
  let stage: Stage
  let gate: InstallationGate
  private let lock = NSLock()
  private var suppressed = false
  private var closes = 0
  private var activations = 0
  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }

  init(stage: Stage, gate: InstallationGate) {
    self.stage = stage
    self.gate = gate
  }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    lock.withLock { activations += 1 }
    if stage == .activation { await gate.suspend() }
  }

  func setOutputSuppressed(_ value: Bool) async {
    if stage == .suppression { await gate.suspend() }
    suppressOutput = value
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {}

  func close() async {
    if stage == .retirement { await gate.suspend() }
    lock.withLock { closes += 1 }
  }

  func counts() -> (activations: Int, closes: Int) { lock.withLock { (activations, closes) } }
}

struct AutomaticDispatcherCoordinatorTests {
  private let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

  @Test(.timeLimit(.minutes(1)))
  func installationUsesSuppressionChangedDuringSuspension() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: .suppression, gate: gate)
    async let pending = coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    await coordinator.synchronizeSuppression { true }
    await gate.release()
    let lease = await pending
    try #require(lease != nil)
    #expect(backend.suppressOutput)
    await lease?.release()
    await coordinator.close()
    #expect(backend.counts().closes == 1)
  }

  @Test(
    .timeLimit(.minutes(1)),
    arguments: [InstallationBackend.Stage.activation, .suppression],
    [false, true]
  )
  private func stopDrainsSuspendedInstallation(
    stage: InstallationBackend.Stage,
    shutdown: Bool
  ) async {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: stage, gate: gate)
    async let lease = coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    async let stopped: Void = shutdown ? coordinator.close() : coordinator.stop(identifier)
    await gate.waitForCancellation()
    #expect(backend.counts().closes == 0)
    await gate.release()
    await stopped
    #expect(await lease == nil)
    #expect(backend.counts().closes == 1)
    let stale = await coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      isEligible: { _, _ in true },
      factory: { _ in backend }
    )
    #expect(stale == nil)
    await coordinator.close()
    #expect(backend.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func closeDuringRetirementNeverActivatesReplacement() async throws {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let original = InstallationBackend(stage: .retirement, gate: gate)
    let replacement = InstallationBackend(stage: .activation, gate: InstallationGate())
    let lease = await coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      isEligible: { _, _ in true },
      factory: { _ in original }
    )
    try #require(lease != nil)
    await lease?.release()
    async let replaced = coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .appleGameController,
      isEligible: { _, _ in true },
      factory: { _ in replacement }
    )
    await gate.waitForEntry()
    async let closed: Void = coordinator.close()
    await gate.waitForCancellation()
    #expect(original.counts().closes == 0)
    #expect(replacement.counts().activations == 0)
    await gate.release()
    await closed
    #expect(await replaced == nil)
    #expect(original.counts().closes == 1)
    #expect(replacement.counts().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func eligibilityCannotResurrectStoppedController() async {
    let coordinator = AutomaticDispatcherCoordinator()
    let gate = InstallationGate()
    let backend = InstallationBackend(stage: .activation, gate: InstallationGate())
    async let lease = coordinator.leaseForDispatch(
      controller: identifier,
      consumer: .sdlHIDAPI,
      identity: .genericHID,
      isEligible: { _, _ in
        await gate.suspend()
        return true
      },
      factory: { _ in backend }
    )
    await gate.waitForEntry()
    await coordinator.stop(identifier)
    await gate.release()
    #expect(await lease == nil)
    #expect(backend.counts().activations == 0)
    await coordinator.close()
  }
}
