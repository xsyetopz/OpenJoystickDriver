import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTransitionTests {
  @Test
  func noncooperativeFeedbackIsQuarantinedBeforeNeutralization() async {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let stalledWrite = VirtualOutputTransitionGate()
    let probe = VirtualOutputFeedbackProbe()
    let feedbackGate = VirtualOutputFeedbackGate { _, command in
      await probe.append(command)
      if command != .stopRumble { await stalledWrite.wait() }
    }

    let rumble = RumbleIntensities(leftMain: UnipolarValue(byte: 1))
    feedbackGate.submit(
      identifier: identifier,
      command: .setRumble(rumble, duration: .milliseconds(250))
    )
    while await probe.count() < 1 { await Task.yield() }

    let started = DispatchTime.now().uptimeNanoseconds
    #expect(await feedbackGate.quiesceAndNeutralize([identifier], timeout: 20_000_000))
    let elapsed = DispatchTime.now().uptimeNanoseconds - started
    #expect(elapsed < 100_000_000)
    #expect(await probe.values().last == .stopRumble)

    await stalledWrite.open()
  }

  @Test
  func quiescingOneControllerLeavesIdenticalControllerFeedbackFlowing() async {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)
    let stalledNeutralization = VirtualOutputTransitionGate()
    let sent = Locked<[DeviceIdentifier]>([])
    let feedbackGate = VirtualOutputFeedbackGate { identifier, _ in
      sent.withLock { $0.append(identifier) }
      if identifier == first { await stalledNeutralization.wait() }
    }

    let quiesce = Task {
      await feedbackGate.quiesceAndNeutralize(
        [first],
        timeout: 1_000_000_000,
        resumeWhenComplete: true
      )
    }
    while sent.withLock({ $0.isEmpty }) { await Task.yield() }

    // Mid-transition, the other controller's feedback is admitted and the first one's is not.
    feedbackGate.submit(identifier: first, command: .stopRumble)
    feedbackGate.submit(identifier: second, command: .stopRumble)
    while !sent.withLock({ $0.contains(second) }) { await Task.yield() }
    #expect(sent.withLock { $0 } == [first, second])

    await stalledNeutralization.open()
    #expect(await quiesce.value)

    feedbackGate.submit(identifier: first, command: .stopRumble)
    while sent.withLock({ $0.count }) < 3 { await Task.yield() }
    #expect(sent.withLock { $0 } == [first, second, first])
  }

  @Test
  func consumerFeedbackMapsOntoThePhysicalCommand() {
    let rumble = RumbleIntensities(
      leftMain: UnipolarValue(byte: 1),
      rightMain: UnipolarValue(byte: 2),
      leftTrigger: UnipolarValue(byte: 3),
      rightTrigger: UnipolarValue(byte: 4)
    )
    // The main motors are mirrored onto the Steam trackpad haptics, as the manual path does.
    let mirrored = RumbleIntensities(
      leftMain: UnipolarValue(byte: 1),
      rightMain: UnipolarValue(byte: 2),
      leftTrigger: UnipolarValue(byte: 3),
      rightTrigger: UnipolarValue(byte: 4),
      leftHaptic: UnipolarValue(byte: 1),
      rightHaptic: UnipolarValue(byte: 2)
    )
    #expect(
      VirtualOutputFeedbackGate.physicalFeedback(
        for: .setRumble(rumble, duration: .milliseconds(50))
      ) == .setRumble(mirrored, duration: .milliseconds(50))
    )
    #expect(VirtualOutputFeedbackGate.physicalFeedback(for: .stopRumble) == .stopRumble)
    #expect(
      VirtualOutputFeedbackGate.physicalFeedback(for: .setRumble(rumble, duration: .held)) == nil
    )
    #expect(VirtualOutputFeedbackGate.physicalFeedback(for: .setPlayerIndicator(.player1)) == nil)
    #expect(
      VirtualOutputFeedbackGate.physicalFeedback(
        for: .setRGB(ControllerColor(red: 1, green: 2, blue: 3))
      ) == nil
    )
  }

  @Test
  func startupActivationPublishesForConnectedControllers() async throws {
    let first = DeviceIdentifier(vendorID: 1, productID: 2)
    let second = DeviceIdentifier(vendorID: 3, productID: 4)
    let factory = VirtualOutputTransitionFactory()
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [first, second]
    )
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices())
    let candidate = try #require(factory.values().first)
    #expect(factory.values().count == 1)
    #expect(candidate.activationValues == [[first], [second]])
    #expect(server.userSpaceDispatcher === candidate)
    #expect(server.userSpaceEnabled)
    #expect(server.userSpaceStatus == .backend("probe"))
    await fixture.tearDown()
  }

  @Test
  func zeroControllersPublishAnIdleBackendForFutureHotPlug() async throws {
    let factory = VirtualOutputTransitionFactory()
    let fixture = try VirtualOutputTransitionFixture(factory: factory, identifiers: [])
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices())
    #expect(factory.values().first?.activationValues == [[]])
    #expect(server.userSpaceDispatcher === factory.values().first)
    #expect(server.userSpaceEnabled)
    await fixture.tearDown()
  }

  @Test
  func activationLeavesLiveOutputUntouched() async throws {
    let factory = VirtualOutputTransitionFactory()
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let server = fixture.server
    let live = VirtualOutputTransitionProbe()
    fixture.installLive(live)

    #expect(await server.activateVirtualOutputBackendForCurrentDevices())
    #expect(factory.values().isEmpty)
    #expect(live.activationValues.isEmpty)
    #expect(live.closeCountValue == 0)
    #expect(server.userSpaceDispatcher === live)
    await fixture.tearDown()
  }

  @Test
  func buildFailureLeavesOutputUnavailableWithTheError() async throws {
    let factory = VirtualOutputTransitionFactory()
    factory.buildFails = true
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.userSpaceStatus.isError)
    #expect(server.userSpaceStatusSnapshot().enabled == false)
    await fixture.tearDown()
  }

  @Test
  func activationFailureClosesTheCandidate() async throws {
    let factory = VirtualOutputTransitionFactory()
    factory.activationFails = true
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)
    #expect(factory.values().count == 1)
    #expect(factory.values().first?.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.userSpaceStatus.isError)
    await fixture.tearDown()
  }

  @Test
  func hangingActivationTimesOutAndClosesTheCandidate() async throws {
    let gate = VirtualOutputTransitionGate()
    let factory = VirtualOutputTransitionFactory()
    factory.firstActivationGate = gate
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)],
      timeouts: VirtualOutputTransitionTimeouts(
        stageNanoseconds: 100_000_000,
        perControllerNanoseconds: 5_000_000,
        totalNanoseconds: 5_000_000
      )
    )
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)
    #expect(factory.values().first?.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceStatus.isError)

    await gate.open()
    await Task.yield()
    #expect(server.userSpaceDispatcher == nil)
    #expect(factory.values().count == 1)
    await fixture.tearDown()
  }

  @Test
  func stopDuringActivationPreventsPublication() async throws {
    let gate = VirtualOutputTransitionGate()
    let factory = VirtualOutputTransitionFactory()
    factory.firstActivationGate = gate
    let first = DeviceIdentifier(vendorID: 1, productID: 2)
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [first, DeviceIdentifier(vendorID: 3, productID: 4)]
    )
    let server = fixture.server
    let activation = Task { await server.activateVirtualOutputBackendForCurrentDevices() }
    await factory.waitForCount(1)
    // A later queued operation takes the queue's tail, so stopping cannot cancel the activation
    // and only the server's stopped state ends it.
    let reset = Task { await server.resetSettings() }
    try await Task.sleep(nanoseconds: 50_000_000)

    let stop = Task { await server.stop() }
    while !server.isVirtualOutputServerStopped() { await Task.yield() }
    await gate.open()
    await stop.value
    #expect(await activation.value == false)
    #expect(await reset.value == false)
    #expect(factory.values().count == 1)
    #expect(factory.values().first?.activationValues == [[first]])
    #expect(factory.values().first?.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.userSpaceStatus == .off)
    await fixture.tearDown()
  }

  @Test
  func stopClosesTheLiveBackendAndDisablesOutput() async throws {
    let factory = VirtualOutputTransitionFactory()
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let server = fixture.server
    let live = VirtualOutputTransitionProbe()
    fixture.installLive(live)

    await server.stop()
    #expect(live.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceEnabled == false)
    #expect(server.userSpaceStatus == .off)
    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)
    #expect(factory.values().isEmpty)
    await fixture.tearDown()
  }

  @Test
  func resetSettingsRestoresUnavailableOutput() async throws {
    let factory = VirtualOutputTransitionFactory()
    factory.buildFails = true
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: [DeviceIdentifier(vendorID: 1, productID: 2)]
    )
    let server = fixture.server
    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)

    factory.buildFails = false
    let reset = await server.resetSettings()
    #expect(reset)
    #expect(server.userSpaceDispatcher === factory.values().first)
    #expect(server.userSpaceEnabled)
    #expect(server.userSpaceStatus == .backend("probe"))
    await fixture.tearDown()
  }

  @Test
  func aNewServerPublishesOutputOnlyThroughActivation() async throws {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    let factory = VirtualOutputTransitionFactory()
    let fixture = try VirtualOutputTransitionFixture(factory: factory, identifiers: [identifier])
    let server = fixture.server
    #expect(server.userSpaceDispatcher == nil)
    #expect(factory.values().isEmpty)

    #expect(await server.activateVirtualOutputBackendForCurrentDevices())
    #expect(factory.values().count == 1)
    #expect(factory.values().first?.activationValues == [[identifier]])
    #expect(server.userSpaceDispatcher === factory.values().first)
    await fixture.tearDown()
  }

  @Test
  func theTotalBudgetBoundsActivationAcrossControllers() async throws {
    let identifiers = (1...3).map { DeviceIdentifier(vendorID: UInt16($0), productID: 2) }
    let factory = VirtualOutputTransitionFactory()
    // Each reading advances the clock 40 ns, so every activation takes 40 ns against a 60 ns
    // per-controller and a 100 ns total budget; three controllers would need 120 ns.
    let ticks = VirtualOutputTransitionTicks(step: 40)
    let fixture = try VirtualOutputTransitionFixture(
      factory: factory,
      identifiers: identifiers,
      timeouts: VirtualOutputTransitionTimeouts(
        stageNanoseconds: 2_000_000_000,
        perControllerNanoseconds: 60,
        totalNanoseconds: 100
      ),
      clock: VirtualOutputTransitionClock(
        now: { ticks.next() },
        sleep: { _ in try await Task.sleep(nanoseconds: 60_000_000_000) }
      )
    )
    let server = fixture.server

    #expect(await server.activateVirtualOutputBackendForCurrentDevices() == false)
    #expect(factory.values().first?.activationValues == identifiers.prefix(2).map { [$0] })
    #expect(factory.values().first?.closeCountValue == 1)
    #expect(server.userSpaceDispatcher == nil)
    #expect(server.userSpaceStatus.isError)
    await fixture.tearDown()
  }
}

/// A clock reading that advances by `step` each time it is read.
private final class VirtualOutputTransitionTicks: @unchecked Sendable {
  private let lock = NSLock()
  private let step: UInt64
  private var value: UInt64 = 0

  init(step: UInt64) { self.step = step }

  func next() -> UInt64 {
    lock.withLock {
      defer { value += step }
      return value
    }
  }
}
