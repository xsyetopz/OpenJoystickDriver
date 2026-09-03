import Combine
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

private struct RecordedRumble: Equatable, Sendable {
  let selector: RuntimeDeviceSelector
  let left: UInt8
  let right: UInt8
  let leftTrigger: UInt8
  let rightTrigger: UInt8
  let durationMilliseconds: Int
}

private actor InputTestGatewayStub: InputTestDeviceGateway {
  var inputSequence: [DeviceInputState?]
  var inputDelayNanoseconds: UInt64
  var outputDelayNanoseconds: UInt64
  var inputCalls = 0
  var cancelledInputCalls = 0
  var activeInputCalls = 0
  var maximumConcurrentInputCalls = 0
  var inputSelectors: [RuntimeDeviceSelector] = []
  var rumbleCalls: [RecordedRumble] = []
  var playerCalls: [(RuntimeDeviceSelector, PhysicalPlayerIndicator)] = []
  var colorCalls: [(RuntimeDeviceSelector, UInt8, UInt8, UInt8)] = []
  var brightnessCalls: [(RuntimeDeviceSelector, UInt8)] = []
  var outputResult = true
  var activeOutputCalls = 0
  var maximumConcurrentOutputCalls = 0

  init(
    inputSequence: [DeviceInputState?] = [],
    inputDelayNanoseconds: UInt64 = 0,
    outputDelayNanoseconds: UInt64 = 0
  ) {
    self.inputSequence = inputSequence
    self.inputDelayNanoseconds = inputDelayNanoseconds
    self.outputDelayNanoseconds = outputDelayNanoseconds
  }

  func inputState(for selector: RuntimeDeviceSelector) async throws -> DeviceInputState? {
    inputCalls += 1
    activeInputCalls += 1
    maximumConcurrentInputCalls = max(maximumConcurrentInputCalls, activeInputCalls)
    inputSelectors.append(selector)
    defer { activeInputCalls -= 1 }
    if inputDelayNanoseconds > 0 {
      do { try await Task.sleep(nanoseconds: inputDelayNanoseconds) } catch {
        cancelledInputCalls += 1
        throw error
      }
    }
    guard !inputSequence.isEmpty else { return nil }
    return inputSequence.removeFirst()
  }

  func sendRumble(
    for selector: RuntimeDeviceSelector,
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8,
    rightTrigger: UInt8,
    durationMilliseconds: Int
  ) async throws -> Bool {
    try await beginOutputCall()
    defer { finishOutputCall() }
    rumbleCalls.append(
      RecordedRumble(
        selector: selector,
        left: left,
        right: right,
        leftTrigger: leftTrigger,
        rightTrigger: rightTrigger,
        durationMilliseconds: durationMilliseconds
      )
    )
    return outputResult
  }

  func setPlayerIndicator(for selector: RuntimeDeviceSelector, indicator: PhysicalPlayerIndicator)
    async throws -> Bool
  {
    try await beginOutputCall()
    defer { finishOutputCall() }
    playerCalls.append((selector, indicator))
    return outputResult
  }

  func setColor(for selector: RuntimeDeviceSelector, red: UInt8, green: UInt8, blue: UInt8)
    async throws -> Bool
  {
    try await beginOutputCall()
    defer { finishOutputCall() }
    colorCalls.append((selector, red, green, blue))
    return outputResult
  }

  func setBrightness(for selector: RuntimeDeviceSelector, brightness: UInt8) async throws -> Bool {
    try await beginOutputCall()
    defer { finishOutputCall() }
    brightnessCalls.append((selector, brightness))
    return outputResult
  }

  func counts() -> (
    input: Int, cancelled: Int, maximumConcurrentInput: Int, maximumConcurrentOutput: Int,
    rumble: Int, player: Int, color: Int, brightness: Int
  ) {
    (
      inputCalls, cancelledInputCalls, maximumConcurrentInputCalls, maximumConcurrentOutputCalls,
      rumbleCalls.count, playerCalls.count, colorCalls.count, brightnessCalls.count
    )
  }

  func setOutputResult(_ result: Bool) { outputResult = result }

  func waitForInputCalls(_ expectedCount: Int) async -> Bool {
    for _ in 0..<100 {
      if inputCalls >= expectedCount { return true }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return inputCalls >= expectedCount
  }

  private func beginOutputCall() async throws {
    activeOutputCalls += 1
    maximumConcurrentOutputCalls = max(maximumConcurrentOutputCalls, activeOutputCalls)
    if outputDelayNanoseconds > 0 {
      do { try await Task.sleep(nanoseconds: outputDelayNanoseconds) } catch {
        // Callers install their cleanup defer only after this helper returns successfully.
        activeOutputCalls -= 1
        throw error
      }
    }
  }

  private func finishOutputCall() { activeOutputCalls -= 1 }
}

@Suite(.serialized) struct InputTestTests {
  @Test @MainActor func selectingDeviceRemainsIdleUntilExplicitStart() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)

    model.selectDevice(makeInputTestDevice())
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(model.sessionState == .idle)
    #expect(await gateway.counts().input == 0)
  }

  @Test @MainActor func startSamplesSequentiallyAndStopCancelsTheActiveLookup() async {
    var first = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    first.pressedButtons = ["A"]
    let gateway = InputTestGatewayStub(inputSequence: [first], inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)
    #expect(model.sessionState == .starting)
    #expect(await gateway.counts().input == 1)

    model.stop()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .idle)
    #expect(await gateway.counts().cancelled == 1)
    #expect(await gateway.counts().input == 1)
  }

  @Test @MainActor func liveSamplingPublishesNormalizedState() async {
    var pressed = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    pressed.pressedButtons = ["A", "D-pad Up"]
    pressed.leftStickX = 0.75
    pressed.rightTrigger = 0.5
    let gateway = InputTestGatewayStub(inputSequence: [pressed])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())

    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .live)
    #expect(model.latestInput == pressed)
    #expect(await gateway.inputSelectors == [RuntimeDeviceSelector(device: makeInputTestDevice())])
    model.stop()
  }

  @Test @MainActor func unchangedSnapshotsDoNotRepublishInputState() async {
    let snapshot = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 4),
      inputDelayNanoseconds: 1_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())
    var publishedSnapshots = 0
    let observation = model.liveState.$snapshot.dropFirst().sink { _ in publishedSnapshots += 1 }

    model.start()
    let receivedAllSnapshots = await gateway.waitForInputCalls(4)
    model.stop()

    #expect(receivedAllSnapshots)
    #expect(publishedSnapshots == 0)
    withExtendedLifetime(observation) {}
  }

  @Test @MainActor func liveInputUpdatesDoNotInvalidateTheSessionAndOutputModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }
    var snapshot = model.latestInput
    snapshot.leftStickX = 0.75
    snapshot.pressedButtons = [Button.a.rawValue]

    model.liveState.update(snapshot)

    #expect(model.latestInput == snapshot)
    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test @MainActor func outputControlChangesDoNotInvalidateTheSessionModel() {
    let model = InputTestViewModel(gateway: InputTestGatewayStub())
    model.selectDevice(makeInputTestDevice())
    var broadInvalidations = 0
    let observation = model.objectWillChange.sink { broadInvalidations += 1 }

    model.rumbleDurationMilliseconds = 750
    model.rumbleIntensities[.leftMain] = 128
    model.brightness = 192

    #expect(broadInvalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test @MainActor func repeatedUnavailableSamplesStopTheLoopWithoutUnboundedRetry() async {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.start()
    try? await Task.sleep(nanoseconds: 15_000_000)
    let callsAtStop = await gateway.counts().input
    try? await Task.sleep(nanoseconds: 5_000_000)

    #expect(model.sessionState == .unavailable)
    #expect(callsAtStop == 3)
    #expect(await gateway.counts().input == callsAtStop)
  }

  @Test @MainActor func repeatedFailuresRetainTheLastSnapshotAndFinishStale() async {
    var snapshot = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    snapshot.pressedButtons = [Button.a.rawValue]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.start()
    try? await Task.sleep(nanoseconds: 15_000_000)

    #expect(model.sessionState == .stale)
    #expect(model.latestInput == snapshot)
    #expect(await gateway.counts().input == 4)
  }

  @Test func canonicalButtonsDriveTheStandardInputMap() {
    var state = DeviceInputState(vendorID: 1, productID: 2)
    state.pressedButtons = [
      Button.leftBumper.rawValue, Button.dpadUp.rawValue, Button.leftStick.rawValue,
      Button.l2Digital.rawValue, Button.genericButton1.rawValue
    ]

    #expect(InputTestButtonPresentation.isPressed([.leftBumper, .l1], in: state))
    #expect(InputTestButtonPresentation.isPressed([.dpadUp], in: state))
    #expect(InputTestButtonPresentation.isPressed([.leftStick], in: state))
    #expect(InputTestButtonPresentation.isPressed([.l2Digital], in: state))
    #expect(InputTestButtonPresentation.additionalButtons(in: state) == ["genericButton1"])
  }

  @Test func controllerFamiliesSelectProtocolAppropriateInputSymbols() {
    let xbox = InputTestControllerSymbolSet.resolve(for: .xboxOne)
    #expect(xbox.leftShoulder.symbol == "lb.button.roundedbottom.horizontal")
    #expect(xbox.leftTrigger.symbol == "lt.button.roundedtop.horizontal")
    #expect(xbox.guide.symbol == "xbox.logo")
    #expect(xbox.leftStickClick.symbol == "lsb.button.angledbottom.horizontal.left")

    let playStation = InputTestControllerSymbolSet.resolve(for: .dualSense)
    #expect(playStation.leftShoulder.symbol == "l1.button.roundedbottom.horizontal")
    #expect(playStation.leftTrigger.symbol == "l2.button.roundedtop.horizontal")
    #expect(playStation.guide.symbol == "playstation.logo")
    #expect(playStation.southFace.symbol == "xmark.circle")

    let switchController = InputTestControllerSymbolSet.resolve(for: .switchPro)
    #expect(switchController.leftTrigger.symbol == "zl.button.roundedtop.horizontal")
    #expect(switchController.view.symbol == "minus.circle")
    #expect(switchController.menu.symbol == "plus.circle")

    let generic = InputTestControllerSymbolSet.resolve(for: .genericHID)
    #expect(generic.leftShoulder.symbol == nil)
    #expect(generic.leftShoulder.fallbackText == "LB / L1")
    #expect(generic.guide.symbol == "house.fill")
  }

  @Test @MainActor func samplingNeverOverlapsInputRequests() async {
    let snapshot = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    let gateway = InputTestGatewayStub(
      inputSequence: Array(repeating: snapshot, count: 8),
      inputDelayNanoseconds: 5_000_000
    )
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000)
    model.selectDevice(makeInputTestDevice())

    model.start()
    try? await Task.sleep(nanoseconds: 40_000_000)
    model.stop()

    #expect(await gateway.counts().input > 1)
    #expect(await gateway.counts().maximumConcurrentInput == 1)
  }

  @Test @MainActor func switchingDevicesCancelsOldSamplingAndLeavesNewDeviceIdle() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let oldDevice = makeInputTestDevice(runtimeIdentifier: "input-test-old")
    let newDevice = makeInputTestDevice(runtimeIdentifier: "input-test-new")
    model.selectDevice(oldDevice)
    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.selectDevice(newDevice)
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.device?.runtimeIdentifier == newDevice.runtimeIdentifier)
    #expect(model.sessionState == .idle)
    #expect(await gateway.counts().cancelled == 1)
    #expect(await gateway.inputSelectors == [RuntimeDeviceSelector(device: oldDevice)])
  }

  @Test @MainActor func unsupportedOutputControlsNeverDispatch() async {
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

  @Test @MainActor func rumbleMapsDeclaredMotorsAndBinaryValues() async {
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
    try? await Task.sleep(nanoseconds: 30_000_000)

    let calls = await gateway.rumbleCalls
    let active = calls.first {
      $0.left != 0 || $0.right != 0 || $0.leftTrigger != 0 || $0.rightTrigger != 0
    }
    #expect(active?.selector == RuntimeDeviceSelector(device: device))
    #expect(active?.left == 127)
    #expect(active?.right == 0)
    #expect(active?.leftTrigger == 0)
    #expect(active?.rightTrigger == 255)
    #expect(active?.durationMilliseconds == 100)
    model.stopRumble()
  }

  @Test @MainActor func lightingUsesExactRuntimeIdentifierAndDeclaredValues() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .playerIndicator, .programmableColor, .programmableBrightness
    ])
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(capabilities: capabilities)
    let selector = RuntimeDeviceSelector(device: device)
    model.selectDevice(device)
    model.playerIndicator = .player3
    model.red = 12
    model.green = 34
    model.blue = 56
    model.brightness = 78

    model.applyPlayerIndicator()
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.applyColor()
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.applyBrightness()
    try? await Task.sleep(nanoseconds: 10_000_000)

    #expect(await gateway.playerCalls.first?.0 == selector)
    #expect(await gateway.playerCalls.first?.1 == .player3)
    #expect(await gateway.colorCalls.first?.0 == selector)
    #expect(await gateway.colorCalls.first?.1 == 12)
    #expect(await gateway.colorCalls.first?.2 == 34)
    #expect(await gateway.colorCalls.first?.3 == 56)
    #expect(await gateway.brightnessCalls.first?.0 == selector)
    #expect(await gateway.brightnessCalls.first?.1 == 78)
    #expect(await gateway.rumbleCalls.isEmpty)
  }

  @Test @MainActor func outputOperationsRemainSerializedWhenAReplacementCancelsTheFirst() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .programmableColor, .programmableBrightness
    ])
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 100_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))

    model.applyColor()
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.applyBrightness()
    try? await Task.sleep(nanoseconds: 150_000_000)

    #expect(await gateway.counts().maximumConcurrentOutput == 1)
    #expect(await gateway.colorCalls.isEmpty)
    #expect(await gateway.brightnessCalls.count == 1)
  }

  @Test @MainActor func stoppingDelayedRumbleSerializesAZeroCommandAfterCancellation() async {
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 100_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.leftMain] = 200

    model.testRumble()
    try? await Task.sleep(nanoseconds: 10_000_000)
    model.stopRumble()
    try? await Task.sleep(nanoseconds: 150_000_000)

    #expect(await gateway.counts().maximumConcurrentOutput == 1)
    #expect(await gateway.rumbleCalls.count == 1)
    #expect(await gateway.rumbleCalls.first?.left == 0)
    #expect(model.outputState == .idle)
  }

  @Test @MainActor func disconnectedDeviceRejectsEveryPhysicalOutputAction() async {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain],
      lightingFeatures: [.playerIndicator, .programmableColor, .programmableBrightness]
    )
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))
    model.reconcileConnectedDevices([])

    model.testRumble()
    model.applyPlayerIndicator()
    model.applyColor()
    model.applyBrightness()
    try? await Task.sleep(nanoseconds: 20_000_000)

    let counts = await gateway.counts()
    #expect(!model.canSendOutput)
    #expect(counts.rumble == 0)
    #expect(counts.player == 0)
    #expect(counts.color == 0)
    #expect(counts.brightness == 0)
  }

  @Test @MainActor func rejectedOutputRetainsLatestInputAndReportsInlineFailure() async {
    var snapshot = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    snapshot.pressedButtons = ["A"]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    await gateway.setOutputResult(false)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())
    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.testRumble()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.latestInput == snapshot)
    #expect(model.outputState == .failed(.rumble))
    #expect(model.outputError != nil)
    model.stop()
  }

  @Test @MainActor func disconnectCancelsSamplingAndRequiresExplicitRestart() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "HID")
    model.selectDevice(device)
    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.reconcileConnectedDevices([])
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .disconnected)
    #expect(await gateway.counts().cancelled == 1)
    model.reconcileConnectedDevices([device])
    #expect(model.sessionState == .idle)
    #expect(!model.isSampling)
  }

  @Test @MainActor func deniedInputMonitoringDoesNotBlockConnectedRawUSBInput() {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "USB")
    model.selectDevice(device)
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputMonitoring: "denied",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      )
    )

    model.reconcileStatus(status)

    #expect(model.sessionState == .idle)
    #expect(model.isDeviceConnected)
  }

  @Test @MainActor func deniedInputMonitoringStopsSamplingAndReportsPermissionRequirement() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "USB", discoverySource: .hid)
    model.selectDevice(device)
    model.start()
    try? await Task.sleep(nanoseconds: 20_000_000)
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputMonitoring: "denied",
        accessibility: "granted",
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready"
      )
    )

    model.reconcileStatus(status)
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .permissionRequired)
    #expect(await gateway.counts().cancelled == 1)
    #expect(!model.isSampling)
  }

  private func makeInputTestDevice(
    capabilities: PhysicalControllerOutputCapabilities = .dualMainRumble,
    runtimeIdentifier: String = "input-test-device",
    connection: String = "USB",
    discoverySource: ApplicationServiceDeviceDiscoverySource = .rawUSB
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "Generic HID",
      connection: connection,
      discoverySource: discoverySource,
      serialNumber: nil,
      physicalOutputCapabilities: capabilities,
      runtimeIdentifier: runtimeIdentifier
    )
  }
}
