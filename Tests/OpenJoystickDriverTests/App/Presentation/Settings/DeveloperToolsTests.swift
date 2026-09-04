import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite struct DeveloperToolsTests {
  @Test @MainActor func reportsTheNoControllerStateExplicitly() async {
    let model = DeveloperToolsViewModel(gateway: GatewayStub())

    await model.refresh()

    #expect(model.loadState == .noControllers)
    #expect(model.selectedDevice == nil)
  }

  @Test @MainActor func refreshLoadsControllerInputAndExistingPackets() async throws {
    let packet = try packetEntry(timestamp: 1, hex: "01")
    let gateway = GatewayStub(
      statusPayload: statusPayload(device: device()),
      inputState: inputState(button: .mute),
      packetEntries: [packet]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    await model.refresh()

    #expect(model.loadState == .ready)
    #expect(model.packets.map(\.hex) == ["01"])
    #expect(model.observedExtraInputs == [Button.mute.rawValue])
  }

  @Test @MainActor func captureIgnoresTheBaselineAndAppendsNewPackets() async throws {
    let first = try packetEntry(timestamp: 1, hex: "01")
    let second = try packetEntry(timestamp: 2, hex: "02")
    let gateway = GatewayStub(
      statusPayload: statusPayload(device: device()),
      inputState: inputState(button: nil),
      packetSequence: [[first], [first], [first, second]]
    )
    let model = DeveloperToolsViewModel(gateway: gateway, pollIntervalNanoseconds: 1) { _ in
      await Task.yield()
    }
    await model.refresh()

    model.startCapture()
    await waitUntil { model.packets.map(\.hex) == ["02"] }
    model.stopCapture()

    #expect(model.packets.map(\.hex) == ["02"])
    #expect(model.captureState == .stopped)
  }

  @Test @MainActor func refreshStopsAnActiveCapture() async throws {
    let baseline = try packetEntry(timestamp: 1, hex: "01")
    let later = try packetEntry(timestamp: 2, hex: "02")
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [device()]),
      inputState: inputState(button: nil),
      packetEntries: [baseline]
    )
    let model = DeveloperToolsViewModel(gateway: gateway, pollIntervalNanoseconds: 1) { _ in
      await Task.yield()
    }
    await model.refresh()

    model.startCapture()
    await waitUntil { model.isCapturing }
    await model.refresh()
    await gateway.setPacketEntries([baseline, later])
    for _ in 0..<100 { await Task.yield() }

    #expect(!model.isCapturing)
    #expect(model.packets.map(\.hex) == ["01"])
  }

  @Test @MainActor func staleSnapshotCannotReplaceTheSelectedController() async throws {
    let firstDevice = device(runtimeIdentifier: "controller-1")
    let secondDevice = device(runtimeIdentifier: "controller-2")
    let firstPacket = try packetEntry(timestamp: 1, hex: "01")
    let secondPacket = try packetEntry(timestamp: 2, hex: "02")
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [firstDevice, secondDevice]),
      inputStatesByRuntimeIdentifier: [
        firstDevice.runtimeIdentifier: inputState(button: .mute),
        secondDevice.runtimeIdentifier: inputState(button: .touchpad)
      ],
      packetEntriesByRuntimeIdentifier: [
        firstDevice.runtimeIdentifier: [firstPacket], secondDevice.runtimeIdentifier: [secondPacket]
      ],
      deviceReadDelaysNanoseconds: [
        firstDevice.runtimeIdentifier: 50_000_000, secondDevice.runtimeIdentifier: 1_000_000
      ]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    let firstRefresh = Task { await model.refresh() }
    await waitUntil { model.selectedDevice?.runtimeIdentifier == firstDevice.runtimeIdentifier }
    model.selectDevice(runtimeIdentifier: secondDevice.runtimeIdentifier)
    await firstRefresh.value
    await waitUntil { model.packets.map(\.hex) == ["02"] }

    #expect(model.selectedDevice?.runtimeIdentifier == secondDevice.runtimeIdentifier)
    #expect(model.latestInput?.pressedButtons == [Button.touchpad.rawValue])
    #expect(model.packets.map(\.hex) == ["02"])
  }

  @Test @MainActor func latestRefreshRequestWins() async {
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [device()]),
      statusReadDelayNanoseconds: 1_000_000,
      inputState: inputState(button: nil)
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    for _ in 0..<20 { model.requestRefresh() }
    await waitUntil { model.loadState == .ready }

    #expect(model.loadState == .ready)
    #expect(model.selectedDevice?.runtimeIdentifier == "controller-1")
  }

  private func device(runtimeIdentifier: String = "controller-1")
    -> ApplicationServiceDeviceDescription
  {
    ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      protocolVariant: .xboxOne,
      inputEndpoint: 0x82,
      outputEndpoint: 0x02,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  private func statusPayload(device: ApplicationServiceDeviceDescription)
    -> ApplicationServiceStatusPayload
  { statusPayload(devices: [device]) }

  private func statusPayload(devices: [ApplicationServiceDeviceDescription])
    -> ApplicationServiceStatusPayload
  {
    ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
  }

  private func inputState(button: Button?) -> DeviceInputState {
    var state = DeviceInputState(vendorID: 0x1234, productID: 0x5678)
    if let button { state.pressedButtons = [button.rawValue] }
    return state
  }

  private func packetEntry(timestamp: TimeInterval, hex: String) throws -> PacketLogEntry {
    let data = try JSONSerialization.data(withJSONObject: [
      "timestamp": timestamp, "direction": "rx", "hex": hex, "length": 1
    ])
    return try JSONDecoder().decode(PacketLogEntry.self, from: data)
  }

  @MainActor private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<1_000 where !condition() { await Task.yield() }
  }
}
