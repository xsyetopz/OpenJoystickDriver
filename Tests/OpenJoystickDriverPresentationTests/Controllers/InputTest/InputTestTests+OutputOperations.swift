import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  @Test
  @MainActor
  func lightingUsesSessionTokenAndDeclaredValues() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .playerIndicator, .programmableColor, .programmableBrightness,
    ])
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(capabilities: capabilities)
    let selector = ControllerReference.session(device.sessionToken)
    model.selectDevice(device)
    model.playerIndicator = .player3
    model.red = 12
    model.green = 34
    model.blue = 56
    model.brightness = 78

    model.applyPlayerIndicator()
    await waitUntil("!gateway.playerCalls.isEmpty") { await !gateway.playerCalls.isEmpty }
    model.applyColor()
    await waitUntil("!gateway.colorCalls.isEmpty") { await !gateway.colorCalls.isEmpty }
    model.applyBrightness()
    await waitUntil("!gateway.brightnessCalls.isEmpty") { await !gateway.brightnessCalls.isEmpty }

    #expect(await gateway.playerCalls.first?.0 == selector)
    #expect(await gateway.playerCalls.first?.1 == .player3)
    #expect(await gateway.colorCalls.first?.0 == selector)
    #expect(await gateway.colorCalls.first?.1 == 12)
    #expect(await gateway.colorCalls.first?.2 == 34)
    #expect(await gateway.colorCalls.first?.3 == 56)
    #expect(await gateway.brightnessCalls.first?.0 == selector)
    #expect(await gateway.brightnessCalls.first?.1 == 78)
    #expect(await gateway.rumbleCalls.isEmpty)

    model.close()
    await waitUntil("!gateway.colorReleaseCalls.isEmpty") {
      await !gateway.colorReleaseCalls.isEmpty
    }
    #expect(await gateway.colorReleaseCalls.first?.0 == selector)
  }

  @Test
  @MainActor
  func outputOperationsRemainSerializedWhenReplacementCancelsFirst() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .programmableColor, .programmableBrightness,
    ])
    // The first operation holds its call open until it is cancelled; the replacement then runs
    // with no delay, so no wall-clock wait decides the outcome.
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 60_000_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))

    model.applyColor()
    await gateway.waitForActiveOutputCall()
    await gateway.setOutputDelay(0)
    model.applyBrightness()
    await waitUntil("gateway.brightnessCalls.count == 1") {
      await gateway.brightnessCalls.count == 1
    }

    #expect(await gateway.counts().maximumConcurrentOutput == 1)
    #expect(await gateway.colorCalls.isEmpty)
    #expect(await gateway.brightnessCalls.count == 1)
  }

  @Test
  @MainActor
  func stoppingDelayedRumbleSerializesZeroCommandAfterCancellation() async {
    // The first rumble call stays in the stub's delay until the stop cancels it.
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 60_000_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.lowFrequency] = 200

    model.testRumble()
    await gateway.waitForActiveOutputCall()
    await gateway.setOutputDelay(0)
    model.stopRumble()

    await gateway.waitForRumbleCalls(1)
    #expect(await gateway.counts().maximumConcurrentOutput == 1)
    #expect(await gateway.rumbleCalls.count == 1)
    #expect(await gateway.rumbleCalls.first?.left == 0)
    #expect(model.outputState == .idle)
  }

  @Test
  @MainActor
  func failedStopOfRumbleShowsTheFailure() async {
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 60_000_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.lowFrequency] = 200

    model.testRumble()
    await gateway.waitForActiveOutputCall()
    await gateway.setOutputDelay(0)
    await gateway.setOutputThrows(true)
    model.stopRumble()

    await waitUntil("the stop failure shows") { model.outputState == .failed(.rumble) }
    #expect(
      model.outputError == RuntimePresentation.userFacingError(InputTestGatewayError.outputFailed)
    )
  }

  @Test
  @MainActor
  func failedStopOfPreviousRumbleShowsTheFailureOfTheNextTest() async {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency],
      lightingFeatures: [.programmableBrightness]
    )
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 60_000_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))
    model.rumbleIntensities[.lowFrequency] = 200

    model.testRumble()
    await gateway.waitForActiveOutputCall()
    await gateway.setOutputDelay(0)
    await gateway.setOutputThrows(true)
    model.applyBrightness()

    await waitUntil("the stop failure shows") { model.outputState == .failed(.brightness) }
    #expect(
      model.outputError == RuntimePresentation.userFacingError(InputTestGatewayError.outputFailed)
    )
  }

  @Test
  @MainActor
  func failedColorPreviewReleaseShowsTheFailure() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .programmableColor
    ])
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice(capabilities: capabilities))

    model.applyColor()
    await waitUntil("!gateway.colorCalls.isEmpty") { await !gateway.colorCalls.isEmpty }
    await gateway.setReleaseThrows(true)
    model.reconcileConnectedDevices([])

    await waitUntil("the release failure shows") { model.outputState == .failed(.color) }
    #expect(
      model.outputError == RuntimePresentation.userFacingError(InputTestGatewayError.outputFailed)
    )
  }

  @Test
  @MainActor
  func disconnectedDeviceRejectsEveryPhysicalOutputAction() async {
    let capabilities = PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency],
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

  @Test
  @MainActor
  func rejectedOutputRetainsLatestInputAndReportsInlineFailure() async {
    var snapshot = ControllerState.neutral
    snapshot.pressed = [.south]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    await gateway.setOutputResult(false)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())
    model.open()
    await waitUntil("the sample is published") { model.latestInput == snapshot }

    model.testRumble()
    await waitUntil("the rumble fails") { model.outputState == .failed(.rumble) }

    #expect(model.latestInput == snapshot)
    #expect(model.outputState == .failed(.rumble))
    #expect(model.outputError != nil)
    #expect(!model.canStopRumble)
    model.close()
  }

  @Test
  @MainActor
  func failedRumbleClearsOutputOwnershipAndReportsTerminalFailure() async {
    let gateway = InputTestGatewayStub()
    await gateway.setOutputThrows(true)
    let rumbleSleep: InputTestViewModel.Sleep = { _ in }
    let model = InputTestViewModel(gateway: gateway, rumbleSleep: rumbleSleep)
    model.selectDevice(makeInputTestDevice())

    model.testRumble()
    await waitUntil("model.outputState == .failed(.rumble)") {
      model.outputState == .failed(.rumble)
    }

    #expect(model.outputError != nil)
    #expect(!model.isOutputBusy)
    #expect(!model.canStopRumble)
  }

  @Test
  @MainActor
  func reconnectResumesSamplingWhileWindowRemainsOpen() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "HID")
    model.selectDevice(device)
    model.open()
    await gateway.waitForInputCalls(1)

    model.reconcileConnectedDevices([])
    await waitUntil("the sampling is cancelled") { await gateway.counts().cancelled == 1 }

    #expect(model.sessionState == .disconnected)
    #expect(await gateway.counts().cancelled == 1)
    model.reconcileConnectedDevices([device])
    await gateway.waitForInputCalls(2)
    #expect(model.sessionState == .starting)
    #expect(model.isSampling)
    model.close()
  }

  @Test
  @MainActor
  func deniedInputReadDoesNotBlockConnectedRawUSBInput() {
    let gateway = InputTestGatewayStub()
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "USB")
    model.selectDevice(device)
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputRead: .denied,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )

    model.reconcileStatus(status)

    #expect(model.sessionState == .idle)
    #expect(model.isDeviceConnected)
  }

  @Test
  @MainActor
  func deniedInputReadStopsSamplingAndReportsPermissionRequirement() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "USB", discoverySource: .hid)
    model.selectDevice(device)
    model.open()
    await gateway.waitForInputCalls(1)
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputRead: .denied,
        inputInject: .granted,
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )

    model.reconcileStatus(status)
    await waitUntil("the sampling is cancelled") { await gateway.counts().cancelled == 1 }

    #expect(model.sessionState == .permissionRequired)
    #expect(await gateway.counts().cancelled == 1)
    #expect(!model.isSampling)
  }

  func makeInputTestDevice(
    capabilities: PhysicalControllerOutputCapabilities = .dualMainRumble,
    hasMotion: Bool = false,
    controls: Set<Control> = [],
    touchContactCount: UInt8 = 0,
    sessionToken: String = "input-device",
    connection: String = "USB",
    discoverySource: DeviceDiscoverySource = .rawUSB
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: connection,
      discoverySource: discoverySource,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: capabilities,
      recordServer: .system,
      recordAccessRoute: .system,
      capabilities: ControllerCapabilities(
        controls: controls,
        touchContactCount: touchContactCount,
        motion: hasMotion
      ),
      sessionToken: .fixture(sessionToken)
    )
  }
}
