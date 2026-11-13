import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  @Test
  @MainActor
  func calibrationSelectionFollowsDisconnectAndClose() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    let device = makeInputTestDevice()
    model.selectDevice(device)
    #expect(model.motionCalibration.selector == ControllerReference.session(device.sessionToken))
    model.reconcileConnectedDevices([])
    #expect(model.motionCalibration.selector == nil)
    model.reconcileConnectedDevices([device])
    #expect(model.motionCalibration.selector == ControllerReference.session(device.sessionToken))
    model.close()
    #expect(model.motionCalibration.selector == nil)
  }

  @Test
  @MainActor
  func openingStartsSamplingImmediately() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)

    model.selectDevice(makeInputTestDevice())
    model.open()
    await gateway.waitForInputCalls(1)

    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().input > 0)
    model.close()
  }

  @Test
  @MainActor
  func closeCancelsTheActiveLookup() async {
    var first = ControllerState.neutral
    first.pressed = [.south]
    let gateway = InputTestGatewayStub(inputSequence: [first], inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    await gateway.waitForInputCalls(1)
    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().input == 1)

    model.close()
    await waitUntil("the lookup is cancelled") { await gateway.counts().cancelled > 0 }

    #expect(model.sessionState == .idle)
    #expect(await gateway.counts().cancelled == 1)
    #expect(await gateway.counts().input == 1)
  }

  @Test
  @MainActor
  func liveSamplingPublishesNormalizedState() async {
    var pressed = ControllerState.neutral
    pressed.pressed = [.south]
    pressed.hat = .north
    pressed.leftStick.x = BipolarValue(normalized: 0.75)
    pressed.rightTrigger = UnipolarValue(normalized: 0.5)
    let gateway = InputTestGatewayStub(inputSequence: [pressed])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    await waitUntil("the sample is published") { model.latestInput == pressed }

    #expect(model.sessionState == .live)
    #expect(model.latestInput == pressed)
    #expect(
      await gateway.inputSelectors == [
        ControllerReference.session(makeInputTestDevice().sessionToken)
      ]
    )
    model.close()
  }

  @Test
  @MainActor
  func statusReadsInputActiveOnlyAfterControlLeavesRest() async {
    var pressed = ControllerState.neutral
    pressed.pressed = [.south]
    let gateway = InputTestGatewayStub(inputSequence: [.neutral, pressed, .neutral])
    let recorder = SessionStateRecorder()
    let model = InputTestViewModel(
      gateway: gateway,
      sampleIntervalNanoseconds: 1_000_000
    ) { _ in await recorder.record() }
    recorder.model = model
    model.selectDevice(makeInputTestDevice())

    model.open()
    await waitUntil("three samples are read") { recorder.states.count >= 3 }
    model.close()

    #expect(recorder.states.prefix(3) == [.receiving, .live, .live])
  }

  @Test
  @MainActor
  func stickLeavingCenterOrTriggerPressedCountsAsInput() {
    var stick = ControllerState.neutral
    stick.leftStick.x = BipolarValue(normalized: 0.5)
    var trigger = ControllerState.neutral
    trigger.leftTrigger = UnipolarValue(normalized: 0.5)
    var hat = ControllerState.neutral
    hat.hat = .north

    #expect(!ControllerState.neutral.hasControlOffRest)
    #expect(stick.hasControlOffRest)
    #expect(trigger.hasControlOffRest)
    #expect(hat.hasControlOffRest)
  }

  @Test
  @MainActor
  func unchangedSnapshotsDoNotRepublishInputState() async {
    let snapshot = ControllerState.neutral
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 4),
      inputDelayNanoseconds: 1_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())
    var publishedSnapshots = 0
    let observation = model.liveState.$snapshot.dropFirst().sink { _ in publishedSnapshots += 1 }

    model.open()
    await gateway.waitForInputCalls(4)
    model.close()

    #expect(publishedSnapshots == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func liveInputUpdatesDoNotInvalidateTheSessionAndOutputModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }
    var snapshot = model.latestInput
    snapshot.leftStick.x = BipolarValue(normalized: 0.75)
    snapshot.pressed = [.south]

    model.liveState.update(snapshot)

    #expect(model.latestInput == snapshot)
    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func outputControlChangesDoNotInvalidateTheSessionModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }

    model.rumbleDurationMilliseconds = 750
    model.rumbleIntensities[.lowFrequency] = 128
    model.brightness = 192

    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func repeatedUnavailableSamplesStopTheLoopWithoutUnboundedRetry() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    await waitUntil("model.sessionState == .unavailable") { model.sessionState == .unavailable }
    let callsAtStop = await gateway.counts().input
    try? await Task.sleep(nanoseconds: 5_000_000)

    #expect(model.sessionState == .unavailable)
    #expect(callsAtStop == 3)
    #expect(await gateway.counts().input == callsAtStop)
  }

  @Test
  @MainActor
  func statusRefreshRecoversAStoppedAutomaticSession() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    let device = makeInputTestDevice()
    model.selectDevice(device)
    model.open()
    await waitUntil("model.sessionState == .unavailable") { model.sessionState == .unavailable }

    model.reconcileConnectedDevices([device])

    await gateway.waitForInputCalls(4)
    model.close()
  }

  @Test
  @MainActor
  func repeatedOpenAndStatusUpdatesKeepOneSamplingTask() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice()
    model.selectDevice(device)

    model.open()
    model.open()
    model.reconcileConnectedDevices([device])
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(await gateway.counts().input == 1)
    #expect(await gateway.counts().maximumConcurrentInput == 1)
    model.close()
  }

  @Test
  @MainActor
  func repeatedFailuresRetainTheLastSnapshotAndFinishStale() async {
    var snapshot = ControllerState.neutral
    snapshot.pressed = [.south]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    // One live sample then three nils stops the loop. Wait for all four requests
    // because `.stale` is also the transient state after the first nil.
    await gateway.waitForInputCalls(4)

    #expect(model.sessionState == .stale)
    #expect(model.latestInput == snapshot)
    #expect(await gateway.counts().input == 4)
    #expect(!model.isSampling)
  }

  @Test
  @MainActor
  func samplingNeverOverlapsInputRequests() async {
    let snapshot = ControllerState.neutral
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 8),
      inputDelayNanoseconds: 5_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.open()
    await gateway.waitForInputCalls(2)
    model.close()

    #expect(await gateway.counts().input > 1)
    #expect(await gateway.counts().maximumConcurrentInput == 1)
  }

  @Test
  @MainActor
  func switchingDevicesTransfersAutomaticSamplingOwnership() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let oldDevice = makeInputTestDevice(sessionToken: "input-test-old")
    let newDevice = makeInputTestDevice(sessionToken: "input-test-new")
    model.selectDevice(oldDevice)
    model.open()
    await gateway.waitForInputCalls(1)

    model.selectDevice(newDevice)
    await gateway.waitForInputCalls(2)
    await waitUntil("the first device sampling is cancelled") {
      await gateway.counts().cancelled == 1
    }

    #expect(model.device?.sessionToken.rawValue == newDevice.sessionToken.rawValue)
    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().cancelled == 1)
    #expect(
      await gateway.inputSelectors == [
        ControllerReference.session(oldDevice.sessionToken),
        ControllerReference.session(newDevice.sessionToken),
      ]
    )
    model.close()
  }

  @Test
  @MainActor
  func unsupportedOutputControlsNeverDispatch() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: .none))

    model.testRumble()
    model.applyPlayerIndicator()
    model.applyColor()
    model.applyBrightness()
    try? await Task.sleep(nanoseconds: 10_000_000)

    let counts = await gateway.counts()
    #expect(counts.rumble == 0)
    #expect(counts.player == 0)
    #expect(counts.color == 0)
    #expect(counts.brightness == 0)
  }

  @Test
  @MainActor
  func rumbleMapsDeclaredMotorsAndBinaryValues() async {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftHaptic, .rightTrigger],
      binaryRumbleMotors: [.rightTrigger]
    )
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(capabilities: capabilities)
    model.selectDevice(device)
    model.rumbleIntensities[.leftHaptic] = 127
    model.rumbleIntensities[.rightTrigger] = 1
    model.rumbleDurationMilliseconds = 100

    model.testRumble()
    await gateway.waitForRumbleCalls(1)

    let calls = await gateway.rumbleCalls
    let active = calls.first {
      $0.left != 0 || $0.right != 0 || $0.leftTrigger != 0 || $0.rightTrigger != 0
    }
    #expect(active?.selector == ControllerReference.session(device.sessionToken))
    #expect(active?.left == 127)
    #expect(active?.right == 0)
    #expect(active?.leftTrigger == 0)
    #expect(active?.rightTrigger == 255)
    #expect(active?.durationMilliseconds == 100)
    model.stopRumble()
  }

  @Test
  @MainActor
  func repeatedRumbleRunsCompleteWithOneCommandEach() async {
    let gateway = InputTestGatewayStub()
    let rumbleSleep: InputTestViewModel.Sleep = { _ in }
    let model = InputTestViewModel(gateway: gateway, rumbleSleep: rumbleSleep)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.lowFrequency] = 200

    for expectedCount in 1...3 {
      model.testRumble()
      await waitUntil("model.outputState == .succeeded(.rumble)") {
        model.outputState == .succeeded(.rumble)
      }
      #expect(await gateway.rumbleCalls.count == expectedCount)
      #expect(!model.canStopRumble)
    }

    #expect(
      await gateway.rumbleCalls.allSatisfy { $0.left == 200 && $0.durationMilliseconds == 300 }
    )
  }

  @Test
  @MainActor
  func explicitRumbleStopCancelsTheWaitAndSendsOneZeroCommand() async {
    let gateway = InputTestGatewayStub()
    let rumbleSleep: InputTestViewModel.Sleep = { _ in try await Task.sleep(nanoseconds: .max) }
    let model = InputTestViewModel(gateway: gateway, rumbleSleep: rumbleSleep)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.lowFrequency] = 200

    model.testRumble()
    await gateway.waitForRumbleCalls(1)
    #expect(model.canStopRumble)
    model.stopRumble()
    await gateway.waitForRumbleCalls(2)

    let calls = await gateway.rumbleCalls
    #expect(calls.count == 2)
    #expect(calls[0].left == 200)
    #expect(calls[1].left == 0)
    #expect(calls[1].right == 0)
    #expect(calls[1].durationMilliseconds == 0)
    #expect(model.outputState == .idle)
    #expect(!model.canStopRumble)
  }

}

/// Records the session state of an Input Test model at each wait between samples.
@MainActor
private final class SessionStateRecorder {
  var model: InputTestViewModel?
  var states: [InputTestViewModel.SessionState] = []

  func record() {
    if let model { states.append(model.sessionState) }
  }
}
