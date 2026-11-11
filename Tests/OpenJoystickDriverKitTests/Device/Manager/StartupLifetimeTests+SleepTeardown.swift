import Foundation
import IOKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  @Test
  func systemSleepNeutralizesHIDFeatureOutputAndTearsDownLikeUnplug() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x28DE,
        productID: 0x1102,
        productName: "Steam Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: 90,
        interfaces: [steamHIDInterface(number: 2)]
      ),
      routingAddress: .ioKit(locationID: 90, interfaceNumber: nil)
    )
    // A Steam role writes to its exact connection, which the backend must observe.
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let identifier = try #require(await manager.connectedLogicalControllerIDs().first)
    #expect(
      await manager.sendOutputForTest(
        .setLightBrightness(UnipolarValue(byte: 128)),
        for: identifier
      )
    )

    await manager.systemWillSleep()

    #expect(await manager.isSystemSleeping)
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.permissionWatchTask == nil)
    let parser = SteamControllerDriver()
    let featureReports = await backend.recordedFeatureReports()
    #expect(
      featureReports.contains(
        parser.encoded(.setLightBrightness(UnipolarValue(byte: 0))).onlyReport
      )
    )
    #expect(parser.deactivationWrites().hidFeatures.allSatisfy { featureReports.contains($0) })
    await manager.stop()
  }

  @Test
  func sleepSendsHIDShutdownReportsBeforeDetectionClosesTheSession() async throws {
    let backend = ScriptedHIDAccessBackend(closesSessionWhenStreamEnds: true)
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x28DE,
        productID: 0x1102,
        productName: "Steam Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: 91,
        interfaces: [steamHIDInterface(number: 2)]
      ),
      routingAddress: .ioKit(locationID: 91, interfaceNumber: nil)
    )
    // A Steam role writes to its exact connection, which the backend must observe.
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await manager.markStartedForTest()
    await manager.holdPermissionWatchForTest()
    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(1)
    await backend.yield(.connected(connection: connection, ownership: .exclusive), attempt: 1)
    await waitUntil("!manager.pipelines.isEmpty") { await !manager.pipelines.isEmpty }
    let identifier = try #require(await manager.connectedLogicalControllerIDs().first)
    #expect(
      await manager.sendOutputForTest(
        .setLightBrightness(UnipolarValue(byte: 128)),
        for: identifier
      )
    )

    await manager.systemWillSleep()

    let parser = SteamControllerDriver()
    let featureReports = await backend.recordedFeatureReports()
    #expect(
      featureReports.contains(
        parser.encoded(.setLightBrightness(UnipolarValue(byte: 0))).onlyReport
      )
    )
    #expect(parser.deactivationWrites().hidFeatures.allSatisfy { featureReports.contains($0) })
    #expect(await backend.isSessionClosed())
    #expect(await manager.hidDetectionTask == nil)
    await manager.stop()
  }

  @Test
  func outputRequestedDuringSleepTeardownCannotReenableRumble() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let identifier = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let connection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000031",
      productName: "Rumbling DS4"
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await backend.enableOutputReports()
    #expect(
      await manager.sendManualRumble(
        for: identifier,
        left: 64,
        right: 0,
        lt: 0,
        rt: 0,
        durationMs: 5_000
      )
    )
    let neutralOutputStarted = StartupTestGate()
    let releaseNeutralOutput = StartupTestGate()
    await backend.blockNextNeutralMotorOutput(
      started: neutralOutputStarted,
      release: releaseNeutralOutput
    )

    let sleep = Task { await manager.systemWillSleep() }
    await neutralOutputStarted.wait()
    await backend.clearOutputReports()
    // A new request, and one that already resolved its controller before teardown began.
    #expect(
      !(await manager.sendManualRumble(
        for: identifier,
        left: 255,
        right: 255,
        lt: 0,
        rt: 0,
        durationMs: 5_000
      ))
    )
    #expect(await backend.recordedOutputReports().isEmpty)

    await releaseNeutralOutput.open()
    await sleep.value
    #expect(await manager.rumbleStopTasks.isEmpty)
    await manager.stop()
  }

  @Test
  func duringTeardownOnlyTeardownScopedWritesReachTheController() async throws {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let identifier = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let connection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000032",
      productName: "Teardown-scoped DS4"
    )
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let pipeline = try #require(await manager.pipelines[identifier])
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await backend.enableOutputReports()
    await manager.setManualRumbleForTest(on: identifier)

    await manager.setStoppingForTest(true)
    let outsideScope = await manager.sendEffectiveRumble(
      for: identifier,
      pipeline: pipeline,
      duration: .held
    )
    #expect(outsideScope != .delivered)
    #expect(await backend.recordedOutputReports().isEmpty)
    let teardownWrite = await ControllerTeardownOutput.$isActive.withValue(true) {
      await manager.sendEffectiveRumble(for: identifier, pipeline: pipeline, duration: .held)
    }
    #expect(teardownWrite == .delivered)
    #expect(await backend.recordedOutputReports().count == 1)
    await manager.setStoppingForTest(false)
    await manager.stop()
  }

  @Test
  func startIssuedAfterSleepBeforeTheFirstStartWaitsForWake() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ScriptedHIDAccessBackend())
    )
    await manager.systemWillSleep()
    await manager.start()
    #expect(await manager.isSystemSleeping)
    #expect(await manager.permissionWatchTask == nil)

    await manager.systemDidWake()
    #expect(!(await manager.isSystemSleeping))
    #expect(await manager.permissionWatchTask != nil)
    await manager.stop()
  }

  @Test
  func sleepDuringHIDInitializationLeavesNoControllerAndWakeReattaches() async {
    let dispatcher = GatedStartupOutputDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ScriptedHIDAccessBackend())
    )
    let identifier = LogicalControllerID(
      vendorID: 0x3537,
      productID: 0x1053,
      serialNumber: "gamesir-reconnect",
      locationID: 83
    )
    await manager.markStartedForTest()
    await manager.scheduleHIDDeviceInitialization(
      connection: gameSirConnection(
        id: "00000000-0000-0000-0000-000000000021",
        productName: "GameSir before sleep"
      ),
      ownership: .exclusive
    )
    await dispatcher.waitForBlockedDispatch()
    #expect(await manager.deviceInfos[identifier] != nil)

    let sleep = Task { await manager.systemWillSleep() }
    await waitUntil("the system is sleeping") { await manager.isSystemSleeping }
    await dispatcher.releaseBlockedDispatch()
    await sleep.value
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.hidInitializationTasks.isEmpty)

    // Wake starts the real permission watch; hold it so it cannot tear down this fake HID device.
    await manager.holdPermissionWatchForTest()
    await manager.systemDidWake()
    let reattached = gameSirConnection(
      id: "00000000-0000-0000-0000-000000000022",
      productName: "GameSir after wake"
    )
    await manager.handleHIDEvent(.connected(connection: reattached, ownership: .exclusive))
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == reattached.connectionID)
    #expect(await manager.pipelines[identifier] != nil)
    await manager.stop()
  }

  @Test
  func stopDuringSleepTeardownPreventsRestartOnWake() async {
    let dispatcher = GatedStartupOutputDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ScriptedHIDAccessBackend())
    )
    await manager.markStartedForTest()
    await manager.scheduleHIDDeviceInitialization(
      connection: gameSirConnection(
        id: "00000000-0000-0000-0000-000000000023",
        productName: "GameSir during shutdown"
      ),
      ownership: .exclusive
    )
    await dispatcher.waitForBlockedDispatch()

    let sleep = Task { await manager.systemWillSleep() }
    await waitUntil("the system is sleeping") { await manager.isSystemSleeping }
    await manager.stop()
    await dispatcher.releaseBlockedDispatch()
    await sleep.value

    await manager.systemDidWake()
    #expect(!(await manager.isSystemSleeping))
    #expect(await manager.detectionTasks.isEmpty)
    #expect(await manager.permissionWatchTask == nil)
    #expect(await manager.suspendedControllerIdentities.isEmpty)
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
  }
}
