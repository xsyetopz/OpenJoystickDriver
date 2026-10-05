import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

extension InputTestTests {
  @Test
  @MainActor
  func lightingUsesExactRuntimeIdentifierAndDeclaredValues() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .playerIndicator, .programmableColor, .programmableBrightness,
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
    #expect(await eventually { await !gateway.playerCalls.isEmpty })
    model.applyColor()
    #expect(await eventually { await !gateway.colorCalls.isEmpty })
    model.applyBrightness()
    #expect(await eventually { await !gateway.brightnessCalls.isEmpty })

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
    #expect(await eventually { await !gateway.colorReleaseCalls.isEmpty })
    #expect(await gateway.colorReleaseCalls.first?.0 == selector)
  }

  @Test
  @MainActor
  func outputOperationsRemainSerializedWhenAReplacementCancelsTheFirst() async {
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [
      .programmableColor, .programmableBrightness,
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

  @Test
  @MainActor
  func stoppingDelayedRumbleSerializesAZeroCommandAfterCancellation() async {
    // The first rumble call stays in the stub's delay until the stop cancels it.
    let gateway = InputTestGatewayStub(outputDelayNanoseconds: 60_000_000_000)
    let model = InputTestViewModel(gateway: gateway)
    model.selectDevice(makeInputTestDevice())
    model.rumbleIntensities[.leftMain] = 200

    model.testRumble()
    #expect(await gateway.waitForActiveOutputCall())
    await gateway.setOutputDelay(0)
    model.stopRumble()

    #expect(await gateway.waitForRumbleCalls(1))
    #expect(await gateway.counts().maximumConcurrentOutput == 1)
    #expect(await gateway.rumbleCalls.count == 1)
    #expect(await gateway.rumbleCalls.first?.left == 0)
    #expect(model.outputState == .idle)
  }

  @Test
  @MainActor
  func disconnectedDeviceRejectsEveryPhysicalOutputAction() async {
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

  @Test
  @MainActor
  func rejectedOutputRetainsLatestInputAndReportsInlineFailure() async {
    var snapshot = ControllerState.neutral
    snapshot.pressed = [.faceSouth]
    let gateway = InputTestGatewayStub(inputSequence: [snapshot])
    await gateway.setOutputResult(false)
    let model = InputTestViewModel(gateway: gateway, sampleIntervalNanoseconds: 1_000_000_000)
    model.selectDevice(makeInputTestDevice())
    model.open()
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.testRumble()
    try? await Task.sleep(nanoseconds: 20_000_000)

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
    await waitUntil { model.outputState == .failed(.rumble) }

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
    try? await Task.sleep(nanoseconds: 20_000_000)

    model.reconcileConnectedDevices([])
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .disconnected)
    #expect(await gateway.counts().cancelled == 1)
    model.reconcileConnectedDevices([device])
    #expect(await gateway.waitForInputCalls(2))
    #expect(model.sessionState == .starting)
    #expect(model.isSampling)
    model.close()
  }

  @Test
  @MainActor
  func deniedInputMonitoringDoesNotBlockConnectedRawUSBInput() {
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
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )

    model.reconcileStatus(status)

    #expect(model.sessionState == .idle)
    #expect(model.isDeviceConnected)
  }

  @Test
  @MainActor
  func deniedInputMonitoringStopsSamplingAndReportsPermissionRequirement() async {
    let gateway = InputTestGatewayStub(inputDelayNanoseconds: 200_000_000)
    let model = InputTestViewModel(gateway: gateway)
    let device = makeInputTestDevice(connection: "USB", discoverySource: .hid)
    model.selectDevice(device)
    model.open()
    try? await Task.sleep(nanoseconds: 20_000_000)
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputMonitoring: "denied",
        accessibility: "granted",
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )

    model.reconcileStatus(status)
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(model.sessionState == .permissionRequired)
    #expect(await gateway.counts().cancelled == 1)
    #expect(!model.isSampling)
  }

  func makeInputTestDevice(
    capabilities: PhysicalControllerOutputCapabilities = .dualMainRumble,
    runtimeIdentifier: String = "input-test-device",
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
      runtimeIdentifier: runtimeIdentifier
    )
  }

  @MainActor
  func waitUntil(
    timeoutNanoseconds: UInt64 = 10_000_000_000,
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds
    while !condition() {
      if DispatchTime.now().uptimeNanoseconds >= deadline { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds &+ 10_000_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if await condition() { return true }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await condition()
  }
}
