import Foundation
import IOKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite(.timeLimit(.minutes(2)))
struct StartupLifetimeTests {
  @Test
  func hidManagerTargetsOutputAndFeatureReportsByExactConnection() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = HIDManager(backend: backend)
    let oldConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000041",
      productName: "Old exact-output connection"
    )
    let currentConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000042",
      productName: "Current exact-output connection"
    )
    let report = PhysicalHIDOutputReport(reportID: 5, bytes: [5, 0])
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: oldConnection, ownership: .exclusive),
      HIDDeviceConnectionSnapshot(connection: currentConnection, ownership: .exclusive),
    ])
    await backend.enableOutputReports()

    guard case .success = await manager.setOutputReport(connection: oldConnection, report: report)
    else {
      Issue.record("The exact observed output connection was not targeted")
      return
    }
    guard case .success = await manager.setFeatureReport(connection: oldConnection, report: report)
    else {
      Issue.record("The exact observed feature connection was not targeted")
      return
    }
    #expect(await backend.recordedOutputReportConnectionIDs() == [oldConnection.connectionID])
    #expect(await backend.recordedFeatureReportTargets() == [oldConnection.connectionID])

    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: currentConnection, ownership: .exclusive)
    ])
    guard
      case .unavailable = await manager.setOutputReport(connection: oldConnection, report: report)
    else {
      Issue.record("A detached exact output connection was treated as available")
      return
    }
    guard
      case .unavailable = await manager.setFeatureReport(connection: oldConnection, report: report)
    else {
      Issue.record("A detached exact feature connection was treated as available")
      return
    }
    #expect(await backend.recordedOutputReportConnectionIDs() == [oldConnection.connectionID])
    #expect(await backend.recordedFeatureReportTargets() == [oldConnection.connectionID])
  }

  @Test
  func detachedSteamNeutralFeatureReportsTargetOldTokenWhenLocationOverlaps() async throws {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let oldConnection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x28DE,
        productID: 0x1102,
        productName: "Steam Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: 84,
        interfaces: [steamHIDInterface(number: 2)]
      ),
      routingAddress: .ioKit(locationID: 84, interfaceNumber: nil)
    )
    let overlappingConnection = HIDDeviceConnection(
      physicalDevice: oldConnection.physicalDevice,
      routingAddress: oldConnection.routingAddress
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: oldConnection, ownership: .exclusive),
      HIDDeviceConnectionSnapshot(connection: overlappingConnection, ownership: .exclusive),
    ])
    await backend.enableFeatureReports()
    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    let identifier = try #require(await manager.connectedLogicalControllerIDs().first)
    #expect(
      await manager.sendOutputForTest(
        .setLightBrightness(UnipolarValue(byte: 128)),
        for: identifier
      )
    )

    await manager.handleHIDEvent(.disconnected(connection: oldConnection))

    let neutralBrightness = SteamControllerDriver().encoded(
      .setLightBrightness(UnipolarValue(byte: 0))
    ).onlyReport
    let reports = await backend.recordedFeatureReports()
    let targets = await backend.recordedFeatureReportTargets()
    let neutralTargets = zip(reports, targets).compactMap { report, target in
      report == neutralBrightness ? target : nil
    }
    #expect(!neutralTargets.isEmpty)
    #expect(neutralTargets.allSatisfy { $0 == oldConnection.connectionID })
    #expect(!targets.contains(overlappingConnection.connectionID))
    #expect(await manager.pipelines[identifier] == nil)
    await manager.stop()
  }

  @Test
  func hidManagerReturnsCurrentBackendConnectionSnapshotsUnchanged() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = HIDManager(backend: backend)
    let connection = hidConnection(
      id: "00000000-0000-0000-0000-000000000021",
      productName: "Snapshot controller"
    )
    let expected = [HIDDeviceConnectionSnapshot(connection: connection, ownership: .shared)]
    await backend.setConnectionSnapshots(expected)

    #expect(await manager.currentConnectionSnapshots() == expected)
    #expect(await backend.attemptCount() == 0)
  }

  @Test
  func hidManagerPreservesUnavailableBackendConnectionSnapshot() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = HIDManager(backend: backend)

    await backend.setConnectionSnapshots(nil)

    #expect(await manager.currentConnectionSnapshots() == nil)
    #expect(await backend.attemptCount() == 0)
  }

  @Test
  func immediateRemovalCancelsDelayedInitialization() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x057E,
        productID: 0x2009,
        productName: "Pro Controller",
        transportProperty: "Bluetooth",
        physicalLocationIdentifier: 80,
        interfaces: [hostHIDInterface(.bluetoothClassic)]
      ),
      routingAddress: .ioKit(locationID: 80, interfaceNumber: nil)
    )
    await manager.scheduleHIDDeviceInitialization(connection: connection, ownership: .exclusive)
    let initialization = await manager.hidInitializationTasks.values.first?.task

    await manager.handleHIDEvent(.disconnected(connection: connection))
    await initialization?.value

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func staleDetachDoesNotCancelANewerPendingConnectionAtTheSameRoute() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let oldConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000001",
      productName: "Old connection"
    )
    let newConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000002",
      productName: "Reconnected controller"
    )

    await manager.scheduleHIDDeviceInitialization(connection: oldConnection, ownership: .exclusive)
    await manager.scheduleHIDDeviceInitialization(connection: newConnection, ownership: .exclusive)
    let newInitialization = await manager.hidInitializationTasks.values.first?.task
    await manager.handleHIDEvent(.disconnected(connection: oldConnection))
    await newInitialization?.value

    let identifier = LogicalControllerID(
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "same-device",
      locationID: 80
    )
    #expect(await manager.deviceInfos[identifier]?.physicalDevice == newConnection.physicalDevice)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)

    await manager.handleHIDEvent(.disconnected(connection: newConnection))
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func staleDetachCannotTearDownTheCurrentReconnectedSnapshot() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let oldConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000003",
      productName: "Old connection"
    )
    let newConnection = hidConnection(
      id: "00000000-0000-0000-0000-000000000004",
      productName: "Reconnected controller"
    )
    let identifier = LogicalControllerID(
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "same-device",
      locationID: 80
    )

    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    await manager.handleHIDEvent(.connected(connection: newConnection, ownership: .exclusive))
    await manager.handleHIDEvent(.disconnected(connection: oldConnection))

    #expect(await manager.deviceInfos[identifier]?.physicalDevice == newConnection.physicalDevice)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)
    await manager.handleHIDEvent(.disconnected(connection: newConnection))
    #expect(await manager.deviceInfos[identifier] == nil)
    #expect(await manager.pipelines[identifier] == nil)
    await manager.stop()
  }

  @Test
  func aReconnectKeepsTheLogicalControllerIDAndGetsANewSessionToken() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let connection = hidConnection(
      id: "00000000-0000-0000-0000-000000000006",
      productName: "Reconnecting controller"
    )

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let first = try #require(await manager.connectedControllers().first)
    await manager.handleHIDEvent(.disconnected(connection: connection))
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let second = try #require(await manager.connectedControllers().first)

    #expect(second.logicalControllerID == first.logicalControllerID)
    #expect(second.sessionToken != first.sessionToken)
    #expect(await manager.connectedIdentifier(for: .session(first.sessionToken)) == nil)
    await manager.stop()
  }

  @Test
  func stopCancelsPermissionWatcherBeforeWaitingForHIDInitialization() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let permissionWatchGate = StartupTestGate()
    let initializationGate = StartupTestGate()
    let connection = hidConnection(
      id: "00000000-0000-0000-0000-000000000005",
      productName: "Stopping controller"
    )
    let permissionWatcher = Task {
      await permissionWatchGate.wait()
      await manager.ensureHIDDetectionState(for: .granted)
    }
    let initializationTask = Task { await initializationGate.wait() }
    await manager.installLifecycleTasksForTest(
      permissionWatcher: permissionWatcher,
      initialization: HIDDeviceInitialization(connection: connection, task: initializationTask)
    )

    let stopTask = Task { await manager.stop() }
    await waitUntil("the manager is stopping") { await manager.isStopping }
    await permissionWatchGate.open()
    await permissionWatcher.value

    #expect(await manager.hidDetectionTask == nil)
    await initializationGate.open()
    await stopTask.value
    #expect(await manager.permissionWatchTask == nil)
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.isStopping == false)
  }
}
