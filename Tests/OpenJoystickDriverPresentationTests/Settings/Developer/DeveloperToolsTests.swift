import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct DeveloperToolsTests {
  @Test
  @MainActor
  func closingDuringARefreshLeavesTheDiagnosticsNotLoaded() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let model = DeveloperToolsViewModel(gateway: gateway)

    model.requestRefresh()
    await gateway.waitForStatusCall(count: 1)
    model.close()
    await gateway.resumeNextStatusRead()
    await waitUntil("the cancelled refresh ends") { !model.hasActiveOperation }

    #expect(model.loadState == .idle)
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func closingCancelsARunningSoakTest() async {
    let probe = SoakSamplerProbe()
    let model = DeveloperToolsViewModel(
      gateway: GatewayStub(),
      soakSource: SoakTestModel.Source(
        snapshot: {
          DiagnoseServiceSnapshot(
            availability: .running,
            status: nil,
            virtualDiagnostics: nil,
            frameTimings: nil,
            listenerFailure: .absent
          )
        },
        processIdentifier: { 4_242 },
        sample: probe.sample
      )
    )

    model.soakTest.start()
    await probe.waitUntilSampling()
    model.close()
    await probe.waitUntilCancelled()

    #expect(model.soakTest.state == .idle)
  }

  @Test
  @MainActor
  func showingAdvancedWithDeveloperToolsOnLoadsTheDiagnostics() async throws {
    let gateway = GatewayStub(statusPayload: statusPayload(device: device()))
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.developerTools, to: true)
    let preferences = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
    let sandbox = try CommandLineToolSandbox()
    defer { sandbox.remove() }
    let controller = SettingsWindowController(
      gateway: gateway,
      runtime: RuntimeViewModel(gateway: gateway),
      preferences: preferences,
      commandLineTool: sandbox.model()
    ) { _ in }

    controller.showSettings(pane: .advanced)
    await waitUntil("the diagnostics load") { controller.developerTools.loadState == .ready }
    controller.close()

    #expect(controller.developerTools.loadState == .ready)
  }

  @Test
  @MainActor
  func aRefreshShowsLoadingAtOnceEvenFromAReadyState() async {
    let gateway = GatewayStub(statusPayload: statusPayload(device: device()))
    let model = DeveloperToolsViewModel(gateway: gateway)
    await model.refresh()
    #expect(model.loadState == .ready)

    model.requestRefresh()

    #expect(model.loadState == .loading)
    await waitUntil("the read ends") { !model.hasActiveOperation }
  }

  @Test
  @MainActor
  func aFailedExportOfThePacketCaptureShowsItsReason() throws {
    let model = DeveloperToolsViewModel(gateway: GatewayStub())
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("capture.json")

    model.writePacketCapture(to: missing)
    #expect(model.exportError != nil)

    let writable = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: writable) }
    model.writePacketCapture(to: writable)
    #expect(model.exportError == nil)
  }

  @Test
  @MainActor
  func reportsTheNoControllerStateExplicitly() async {
    let model = DeveloperToolsViewModel(gateway: GatewayStub())

    await model.refresh()

    #expect(model.loadState == .noControllers)
    #expect(model.selectedDevice == nil)
  }

  @Test
  @MainActor
  func refreshLoadsControllerInputAndExistingPackets() async throws {
    let packet = try packetEntry(timestamp: 1, hex: "01")
    let gateway = GatewayStub(
      statusPayload: statusPayload(device: device()),
      inputState: inputState(button: .microphone),
      packetEntries: [packet]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    await model.refresh()

    #expect(model.loadState == .ready)
    #expect(model.packets.map(\.hex) == ["01"])
    #expect(model.observedExtraInputs == [.microphone])
  }

  @Test
  @MainActor
  func sharePressIsListedAsAnExtraInput() async throws {
    let gateway = GatewayStub(
      statusPayload: statusPayload(device: device()),
      inputState: inputState(button: .capture),
      packetEntries: []
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    await model.refresh()

    #expect(model.observedExtraInputs == [.capture])
  }

  @Test
  @MainActor
  func activityFilterHidesGIPHousekeepingInBothDirections() async throws {
    let announce = try packetEntry(timestamp: 1, hex: "02 20 2A 1C 00")
    let status = try packetEntry(timestamp: 2, direction: "Tx", hex: "03 20 2B 00")
    let input = try packetEntry(timestamp: 3, hex: "20 00 47 20 00")
    let gateway = GatewayStub(
      statusPayload: statusPayload(device: device()),
      inputState: inputState(button: nil),
      packetEntries: [announce, status, input]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    await model.refresh()

    #expect(model.packets.map(\.hex) == [announce.hex, status.hex, input.hex])
    #expect(model.displayedPackets.map(\.hex) == [input.hex])
    #expect(model.hiddenIdlePacketCount == 2)
  }

  @Test
  @MainActor
  func filterSwitchesLiveAndExportRemainsComplete() async throws {
    let announce = try packetEntry(timestamp: 1, hex: "02 20")
    let input = try packetEntry(timestamp: 2, hex: "20 00")
    let model = DeveloperToolsViewModel(
      gateway: GatewayStub(
        statusPayload: statusPayload(device: device()),
        inputState: inputState(button: nil),
        packetEntries: [announce, input]
      )
    )
    await model.refresh()

    #expect(model.packetFilter == .activity)
    #expect(model.displayedPackets.map(\.hex) == [input.hex])
    model.packetFilter = .all
    #expect(model.displayedPackets.map(\.hex) == [announce.hex, input.hex])
    #expect(model.hiddenIdlePacketCount == 0)

    let exported = try JSONDecoder().decode([PacketLogEntry].self, from: model.encodedPacketLog())
    #expect(exported.map(\.hex) == [announce.hex, input.hex])
  }

  @Test
  @MainActor
  func preservesDS4BluetoothReportsAsActivityInOrderAndExport() async throws {
    let report = try packetEntry(
      timestamp: 1,
      hex: "11 " + Array(repeating: "00", count: 77).joined(separator: " "),
      length: 78
    )
    let next = try packetEntry(timestamp: 2, hex: "20", length: 1)
    let model = DeveloperToolsViewModel(
      gateway: GatewayStub(
        statusPayload: statusPayload(device: device()),
        inputState: inputState(button: nil),
        packetEntries: [report, next]
      )
    )

    await model.refresh()

    #expect(model.displayedPackets.map(\.hex) == [report.hex, next.hex])
    #expect(model.displayedPackets.first?.length == 78)
    let exported = try JSONDecoder().decode([PacketLogEntry].self, from: model.encodedPacketLog())
    #expect(exported.map(\.hex) == [report.hex, next.hex])
    #expect(exported.map(\.length) == [78, 1])
  }

  @Test
  @MainActor
  func captureIgnoresTheBaselineAndAppendsNewPackets() async throws {
    PlatformHosts.install(FakePlatformHost())
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
    await waitUntil("model.packets.map(\\.hex) == [\"02\"]") { model.packets.map(\.hex) == ["02"] }
    model.stopCapture()

    #expect(model.packets.map(\.hex) == ["02"])
    #expect(model.captureState == .stopped)
  }

  @Test
  @MainActor
  func refreshStopsAnActiveCapture() async throws {
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
    await waitUntil("model.isCapturing") { model.isCapturing }
    await model.refresh()
    await gateway.setPacketEntries([baseline, later])
    for _ in 0..<100 { await Task.yield() }

    #expect(!model.isCapturing)
    #expect(model.packets.map(\.hex) == ["01"])
  }

  @Test
  @MainActor
  func staleSnapshotCannotReplaceTheSelectedController() async throws {
    let firstDevice = device(sessionToken: "controller-1")
    let secondDevice = device(sessionToken: "controller-2")
    let firstPacket = try packetEntry(timestamp: 1, hex: "01")
    let secondPacket = try packetEntry(timestamp: 2, hex: "02")
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [firstDevice, secondDevice]),
      inputStatesBySessionToken: [
        firstDevice.sessionToken.rawValue: inputState(button: .microphone),
        secondDevice.sessionToken.rawValue: inputState(button: .touchpadClick),
      ],
      packetEntriesBySessionToken: [
        firstDevice.sessionToken.rawValue: [firstPacket],
        secondDevice.sessionToken.rawValue: [secondPacket],
      ],
      deviceReadDelaysNanoseconds: [
        firstDevice.sessionToken.rawValue: 50_000_000,
        secondDevice.sessionToken.rawValue: 1_000_000,
      ]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    let firstRefresh = Task { await model.refresh() }
    await waitUntil("the first device is selected") {
      model.selectedDevice?.sessionToken.rawValue == firstDevice.sessionToken.rawValue
    }
    model.selectDevice(sessionToken: secondDevice.sessionToken.rawValue)
    await firstRefresh.value
    await waitUntil("model.packets.map(\\.hex) == [\"02\"]") { model.packets.map(\.hex) == ["02"] }

    #expect(model.selectedDevice?.sessionToken.rawValue == secondDevice.sessionToken.rawValue)
    #expect(model.latestInput?.pressed == [.touchpadClick])
    #expect(model.packets.map(\.hex) == ["02"])
  }

  @Test
  @MainActor
  func latestRefreshRequestWins() async {
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [device()]),
      statusReadDelayNanoseconds: 1_000_000,
      inputState: inputState(button: nil)
    )
    let model = DeveloperToolsViewModel(gateway: gateway)

    for _ in 0..<20 { model.requestRefresh() }
    await waitUntil("model.loadState == .ready") { model.loadState == .ready }

    #expect(model.loadState == .ready)
    #expect(model.selectedDevice?.sessionToken == .fixture("controller-1"))
  }

  @Test
  @MainActor
  func repeatedSwitchingJoinsPredecessorsAndCloseLeavesNoOperation() async throws {
    let firstDevice = device(sessionToken: "controller-1")
    let secondDevice = device(sessionToken: "controller-2")
    let firstPacket = try packetEntry(timestamp: 1, hex: "11")
    let secondPacket = try packetEntry(timestamp: 2, hex: "12")
    let gateway = GatewayStub(
      statusPayload: statusPayload(devices: [firstDevice, secondDevice]),
      inputStatesBySessionToken: [
        firstDevice.sessionToken.rawValue: inputState(button: .microphone),
        secondDevice.sessionToken.rawValue: inputState(button: .touchpadClick),
      ],
      packetEntriesBySessionToken: [
        firstDevice.sessionToken.rawValue: [firstPacket],
        secondDevice.sessionToken.rawValue: [secondPacket],
      ],
      deviceReadDelaysNanoseconds: [
        firstDevice.sessionToken.rawValue: 5_000_000, secondDevice.sessionToken.rawValue: 5_000_000,
      ]
    )
    let model = DeveloperToolsViewModel(gateway: gateway)
    await model.refresh()

    for index in 0..<20 {
      model.selectDevice(
        sessionToken: index.isMultiple(of: 2)
          ? secondDevice.sessionToken.rawValue : firstDevice.sessionToken.rawValue
      )
    }
    model.selectDevice(sessionToken: secondDevice.sessionToken.rawValue)
    await waitUntil("model.packets.map(\\.hex) == [secondPacket.hex]") {
      model.packets.map(\.hex) == [secondPacket.hex]
    }

    #expect(await gateway.maximumConcurrentDeviceReads <= 2)
    model.startCapture()
    await waitUntil("model.isCapturing") { model.isCapturing }
    model.close()
    await waitUntil("!model.hasActiveOperation") { !model.hasActiveOperation }
    #expect(!model.isCapturing)
    #expect(!model.hasActiveOperation)
  }

  private func device(
    sessionToken: String = "controller-1"
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      inputEndpoint: 0x82,
      outputEndpoint: 0x02,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture(sessionToken)
    )
  }

  private func statusPayload(
    device: ApplicationServiceDeviceDescription
  ) -> ApplicationServiceStatusPayload { statusPayload(devices: [device]) }

  private func statusPayload(
    devices: [ApplicationServiceDeviceDescription]
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
  }

  private func inputState(button: Control?) -> ControllerState {
    var state = ControllerState.neutral
    if let button { state.pressed = [button] }
    return state
  }

  private func packetEntry(
    timestamp: TimeInterval,
    direction: String = "Rx",
    hex: String,
    length: Int = 1
  ) throws -> PacketLogEntry {
    let data = try JSONSerialization.data(withJSONObject: [
      "timestamp": timestamp, "direction": direction, "hex": hex, "length": length,
    ])
    return try JSONDecoder().decode(PacketLogEntry.self, from: data)
  }
}
