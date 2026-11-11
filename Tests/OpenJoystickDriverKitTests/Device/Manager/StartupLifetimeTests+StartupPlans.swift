import Foundation
import IOKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  @Test
  func stoppedAndReplacedPipelinesCannotContinueStartup() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 81)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        productName: "Startup test",
        transportProperty: "USB",
        physicalLocationIdentifier: 81,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 81, interfaceNumber: nil)
    )
    let connected = HIDDeviceEvent.connected(connection: connection, ownership: .exclusive)
    await manager.handleHIDEvent(connected)
    let original = try #require(await manager.pipelines[identifier])
    #expect(await manager.isCurrentHIDStartupPipeline(original, connection: connection))
    await manager.handleHIDEvent(
      .ownershipChanged(
        address: .ioKit(locationID: 81, interfaceNumber: nil),
        ownership: .ownedByAnotherClient
      )
    )
    #expect(await manager.isCurrentHIDStartupPipeline(original, connection: connection) == false)
    await manager.handleHIDEvent(
      .ownershipChanged(
        address: .ioKit(locationID: 81, interfaceNumber: nil),
        ownership: .exclusive
      )
    )
    let replacement = try #require(await manager.pipelines[identifier])
    #expect(replacement !== original)
    // Even restarting the stale actor must not authorize its delayed reports on the new device.
    await original.start()
    #expect(await manager.isCurrentHIDStartupPipeline(original, connection: connection) == false)
    #expect(await manager.isCurrentHIDStartupPipeline(replacement, connection: connection))
    await original.stop()
    await manager.stop()
    #expect(await manager.isCurrentHIDStartupPipeline(replacement, connection: connection) == false)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
  }

  @Test
  func staleStartupDoesNotReplaceTheReconnectHeartbeatTask() async throws {
    let dispatcher = GatedStartupOutputDispatcher()
    let manager = DeviceManager(dispatcher: dispatcher, installationKey: testPortKeyInstallationKey)
    let firstConnection = gameSirConnection(
      id: "00000000-0000-0000-0000-000000000011",
      productName: "First GameSir connection"
    )
    let replacementConnection = gameSirConnection(
      id: "00000000-0000-0000-0000-000000000012",
      productName: "Replacement GameSir connection"
    )
    let identifier = LogicalControllerID(
      vendorID: 0x3537,
      productID: 0x1053,
      serialNumber: "gamesir-reconnect",
      locationID: 83
    )

    let firstStartup = Task {
      await manager.handleHIDEvent(.connected(connection: firstConnection, ownership: .exclusive))
    }
    await dispatcher.waitForBlockedDispatch()
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == firstConnection.connectionID)

    await manager.scheduleHIDDeviceInitialization(
      connection: replacementConnection,
      ownership: .exclusive
    )

    var replacementHeartbeat: Task<Void, Never>?
    await waitUntil("the replacement connection has a heartbeat") {
      if await manager.deviceInfos[identifier]?.hidConnectionID
        == replacementConnection.connectionID,
        let task = await manager.hidPeriodicOutputTasks[identifier]
      {
        replacementHeartbeat = task
        return true
      }
      return false
    }
    #expect(replacementHeartbeat != nil)
    guard let replacementHeartbeat else {
      await dispatcher.releaseBlockedDispatch()
      await firstStartup.value
      await manager.stop()
      return
    }

    await dispatcher.releaseBlockedDispatch()
    await firstStartup.value

    #expect(!replacementHeartbeat.isCancelled)
    #expect(
      await manager.deviceInfos[identifier]?.hidConnectionID == replacementConnection.connectionID
    )
    #expect(
      await manager.isCurrentHIDStartupPipeline(
        try #require(await manager.pipelines[identifier]),
        connection: replacementConnection
      )
    )

    await manager.handleHIDEvent(.disconnected(connection: replacementConnection))
    await manager.stop()
  }

  @Test
  func startupPlanRequiresAnActivePipeline() async {
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x057E, productID: 0x2009),
      transport: .hid(address: .ioKit(locationID: 82, interfaceNumber: nil)),
      driver: Switch1Driver(isBluetooth: true),
      dispatcher: LoggingOutputDispatcher()
    )
    #expect(await pipeline.hidStartupWrites().isEmpty)
    await pipeline.start()
    #expect(await pipeline.hidStartupWrites().hidOutputs.count == 5)
    #expect(await pipeline.sessionPlan().hidStartupIntervalNanoseconds == 60_000_000)
    await pipeline.stop()
    #expect(await pipeline.hidStartupWrites().isEmpty)
  }

  /// The pipeline runs the driver's plan with the record's tuning; untuned fields keep the driver
  /// defaults.
  @Test
  func pipelinePlanAppliesTheRecordTuning() async throws {
    let identifier = LogicalControllerID(vendorID: 0x057E, productID: 0x2009)
    let record = try #require(ProtocolDriverRegistry().record(for: identifier.model))
    let tuning = ControllerTuning(
      hidStartupIntervalMilliseconds: 40,
      minimumHIDOutputIntervalMilliseconds: 10,
      hidStartupRecoveryIntervalMilliseconds: 300,
      hidStartupRecoveryRounds: 4
    )
    let defaults = Switch1Driver(isBluetooth: true).sessionPlan
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 83, interfaceNumber: nil)),
      driver: Switch1Driver(isBluetooth: true),
      dispatcher: LoggingOutputDispatcher(),
      binding: ProtocolBinding(
        protocolID: .nintendoSwitch1,
        variant: .bluetoothClassic,
        accessBackend: .hid,
        interfaceNumber: nil,
        rule: .catalogRecord,
        matchedPredicates: [],
        record: record.withRecordID(record.recordID, tuning: tuning)
      )
    )
    let plan = await pipeline.sessionPlan()
    #expect(plan.hidStartupIntervalNanoseconds == 40_000_000)
    #expect(plan.minimumHIDOutputIntervalNanoseconds == 10_000_000)
    #expect(plan.hidStartupRecoveryIntervalNanoseconds == 300_000_000)
    #expect(plan.hidStartupRecoveryRounds == 4)
    #expect(plan.hasStartupRecovery == defaults.hasStartupRecovery)
    #expect(defaults.hidStartupRecoveryRounds == 2)
    #expect(
      DualShock4Driver().sessionPlan
        .tuned(ControllerTuning(inputLivenessTimeoutMilliseconds: 2_500))
        .inputReportLivenessTimeoutNanoseconds == 2_500_000_000
    )
  }

  @Test
  func featureReadsFollowTheBoundVariant() {
    #expect(DualShock4Driver(prefersBluetooth: true).startupFeatureReads().map(\.reportID) == [5])
    #expect(DualShock4Driver().startupFeatureReads().map(\.reportID) == [2])
  }

  @Test
  func ds4BluetoothStartupEnablesFullInputWithoutChangingTheLight() {
    let provider = DualShock4Driver(prefersBluetooth: true)
    let reports = PhysicalProtocolID.sonyDualShock4.protocolDescription.startupWrites(
      phase: .startup,
      variant: .bluetoothClassic,
      parameters: .none
    ).map(\.write).hidOutputs
    let report = reports.first

    #expect(provider.sessionPlan.outputPrecedesFeatureReads)
    #expect(reports.count == 1)
    #expect(report?.reportID == 0x11)
    #expect(report?.bytes.count == 78)
    #expect(report?.bytes[1] == 0xC4)
    #expect(report?.bytes[3] == 0x01)
    #expect(report?.bytes[6...10].allSatisfy { $0 == 0 } == true)
    #expect(report.map { Array($0.bytes[74...77]) } == [0x37, 0x89, 0xFE, 0x89])
    #expect(provider.startupWrites().isEmpty)
    #expect(
      PhysicalProtocolID.sonyDualShock4.protocolDescription.startupWrites(
        phase: .startup,
        variant: .usb,
        parameters: .none
      ).isEmpty
    )
  }

  func hidConnection(id: String, productName: String) -> HIDDeviceConnection {
    HIDDeviceConnection(
      connectionID: UUID(uuidString: id)!,
      physicalDevice: PhysicalDevice(
        vendorID: 0x057E,
        productID: 0x2009,
        productName: productName,
        serialNumber: "same-device",
        transportProperty: "USB",
        physicalLocationIdentifier: 80,
        interfaces: [
          PhysicalInterfaceSignature(
            hostTransport: .usb,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(productName.utf8))
          )
        ]
      ),
      routingAddress: .ioKit(locationID: 80, interfaceNumber: nil)
    )
  }

  func ds4Connection(id: String, productName: String) -> HIDDeviceConnection {
    HIDDeviceConnection(
      connectionID: UUID(uuidString: id)!,
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x09CC,
        productName: productName,
        serialNumber: "teardown-race",
        transportProperty: "Bluetooth",
        physicalLocationIdentifier: nil,
        interfaces: [hostHIDInterface(.bluetoothClassic)]
      ),
      routingAddress: .ioKit(locationID: 82, interfaceNumber: nil)
    )
  }

  func gameSirConnection(id: String, productName: String) -> HIDDeviceConnection {
    HIDDeviceConnection(
      connectionID: UUID(uuidString: id)!,
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: 0x1053,
        productName: productName,
        serialNumber: "gamesir-reconnect",
        transportProperty: "USB",
        physicalLocationIdentifier: 83
      ),
      routingAddress: .ioKit(locationID: 83, interfaceNumber: nil)
    )
  }

  func verifyNewConnectionSurvivesOldTeardown(trigger: HIDTeardownRaceTrigger) async {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let oldConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000013",
      productName: "Old access session"
    )
    let newConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000014",
      productName: "New access session"
    )
    let identifier = LogicalControllerID(
      vendorID: oldConnection.physicalDevice.vendorID!,
      productID: oldConnection.physicalDevice.productID!,
      serialNumber: "same-device",
      locationID: oldConnection.routingAddress.locationID
    )

    await manager.ensureHIDDetectionState(for: .granted)
    let oldDetectionTask = await manager.hidDetectionTask
    await backend.waitForAttempt(1)
    #expect(await backend.attemptCount() == 1)
    await backend.yield(.connected(connection: oldConnection, ownership: .exclusive), attempt: 1)
    await waitUntil("manager.pipelines[identifier] != nil") {
      await manager.pipelines[identifier] != nil
    }
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == oldConnection.connectionID)

    let initializationStarted = StartupTestGate()
    let releaseInitialization = StartupTestGate()
    let noncooperativeInitialization = Task {
      await initializationStarted.open()
      await releaseInitialization.wait()
    }
    await manager.installHIDInitializationForTest(
      HIDDeviceInitialization(connection: oldConnection, task: noncooperativeInitialization)
    )

    var deniedCleanup: Task<Void, Never>?
    switch trigger {
    case .accessFailure: await backend.fail(.notResponding, attempt: 1)
    case .denied: deniedCleanup = Task { await manager.ensureHIDDetectionState(for: .denied) }
    }
    await initializationStarted.wait()
    await waitUntil("manager.hidInitializationTasks.isEmpty") {
      await manager.hidInitializationTasks.isEmpty
    }
    #expect(await manager.hidInitializationTasks.isEmpty)

    if case .accessFailure = trigger {
      // Denial retires the failed session; grant then starts a fresh detector while its older
      // access-failure cleanup is still waiting for the noncooperative initialization task.
      await manager.ensureHIDDetectionState(for: .denied)
    }
    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(2)
    let newDetectionTask = await manager.hidDetectionTask
    let newSessionID = await manager.hidDetectionSessionID
    #expect(await backend.attemptCount() == 2)
    #expect(newSessionID != nil)
    await backend.yield(.connected(connection: newConnection, ownership: .exclusive), attempt: 2)
    await waitUntil("new connection installed with a pipeline") {
      let connectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      let pipeline = await manager.pipelines[identifier]
      return connectionID == newConnection.connectionID && pipeline != nil
    }
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)

    await releaseInitialization.open()
    await noncooperativeInitialization.value
    await deniedCleanup?.value
    if case .denied = trigger { await backend.finish(attempt: 1) }
    await oldDetectionTask?.value
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)
    #expect(await manager.hidDetectionSessionID == newSessionID)
    #expect(await manager.hidDetectionTask != nil)

    await backend.fail(.hostStatus(2), attempt: 2)
    await newDetectionTask?.value
    await manager.stop()
  }
}
