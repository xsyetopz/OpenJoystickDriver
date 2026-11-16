import Foundation
import IOKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  @Test
  func hidAccessFailureTearsDownPhysicalStateAndWaitsForPermissionWatchRetry() async {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let identifier = LogicalControllerID(vendorID: 0x1234, productID: 0x5678, locationID: 85)
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        productName: "Access-failure test controller",
        transportProperty: "USB",
        physicalLocationIdentifier: 85,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 85, interfaceNumber: nil)
    )

    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(1)
    #expect(await backend.attemptCount() == 1)

    await backend.yield(.connected(connection: connection, ownership: .exclusive), attempt: 1)
    await waitUntil("manager.pipelines[identifier] != nil") {
      await manager.pipelines[identifier] != nil
    }
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == connection.connectionID)
    #expect(await manager.pipelines[identifier] != nil)

    await backend.fail(.notResponding, attempt: 1)
    await waitUntil("detection task retired and device info removed") {
      let task = await manager.hidDetectionTask
      let info = await manager.deviceInfos[identifier]
      return task == nil && info == nil
    }
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.hidDetectionSessionID == nil)
    #expect(await manager.deviceInfos[identifier] == nil)
    #expect(await manager.pipelines[identifier] == nil)
    #expect(await backend.attemptCount() == 1)

    // The existing permission watcher invokes this again on its next one-second tick.
    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(2)
    #expect(await backend.attemptCount() == 2)
    await backend.fail(.hostStatus(2), attempt: 2)
    await waitUntil("manager.hidDetectionTask == nil") { await manager.hidDetectionTask == nil }
    await manager.stop()
  }

  @Test
  func staleDetectionCompletionCannotClearNewerDetectionTask() async {
    let backend = ScriptedHIDAccessBackend(delaysFirstStream: true)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )

    await manager.ensureHIDDetectionState(for: .granted)
    let firstTask = await manager.hidDetectionTask
    await backend.waitForAttempt(1)
    #expect(await backend.attemptCount() == 1)

    await manager.ensureHIDDetectionState(for: .denied)
    await manager.ensureHIDDetectionState(for: .granted)
    let secondTask = await manager.hidDetectionTask
    await backend.waitForAttempt(2)
    let secondSessionID = await manager.hidDetectionSessionID
    #expect(await backend.attemptCount() == 2)
    #expect(secondSessionID != nil)

    await backend.releaseFirstStream()
    await firstTask?.value
    #expect(await manager.hidDetectionSessionID == secondSessionID)
    #expect(await manager.hidDetectionTask != nil)

    await backend.fail(.hostStatus(3), attempt: 2)
    await secondTask?.value
    #expect(await manager.hidDetectionTask == nil)
    #expect(await manager.hidDetectionSessionID == nil)
    await manager.stop()
  }

  @Test
  func staleAccessFailureTeardownCannotRemoveConnectionFromNewDetectionSession() async {
    await verifyNewConnectionSurvivesOldTeardown(trigger: .accessFailure)
  }

  @Test
  func staleDeniedTeardownCannotRemoveConnectionStartedBeforeItResumes() async {
    await verifyNewConnectionSurvivesOldTeardown(trigger: .denied)
  }

  @Test
  func reconnectDuringNeutralizationRetainsNewDeviceInfoAndPipeline() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let identifier = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "teardown-race",
      locationID: 82
    )
    let oldConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000006",
      productName: "Old DS4 connection"
    )
    let newConnection = ds4Connection(
      id: "00000000-0000-0000-0000-000000000007",
      productName: "Reconnected DS4"
    )
    await manager.handleHIDEvent(.connected(connection: oldConnection, ownership: .exclusive))
    let oldPipeline = try #require(await manager.pipelines[identifier])
    #expect(!(await oldPipeline.physicalOutputCapabilities()).rumbleMotors.isEmpty)

    let queue = await manager.outputQueueForTest(for: identifier) ?? PhysicalHIDOutputSerialQueue()
    await manager.installOutputQueueForTest(queue, for: identifier)
    let blockerStarted = StartupTestGate()
    let releaseBlocker = StartupTestGate()
    let blockerTask = Task {
      await queue.perform { _ in
        await blockerStarted.open()
        await releaseBlocker.wait()
        return true
      }
    }
    await blockerStarted.wait()

    let detachTask = Task { await manager.handleHIDEvent(.disconnected(connection: oldConnection)) }
    await waitUntil("teardownSuspendedWithOldInfo") {
      let currentPipeline = await manager.pipelines[identifier]
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      return currentPipeline == nil && currentConnectionID == oldConnection.connectionID
    }

    let reconnectTask = Task {
      await manager.handleHIDEvent(.connected(connection: newConnection, ownership: .exclusive))
    }
    await waitUntil("reconnectedInfoIsInstalled") {
      let currentConnectionID = await manager.deviceInfos[identifier]?.hidConnectionID
      let currentPipeline = await manager.pipelines[identifier]
      return currentConnectionID == newConnection.connectionID && currentPipeline != nil
    }

    await releaseBlocker.open()
    #expect(await blockerTask.value == .completed(true))
    await detachTask.value
    await reconnectTask.value

    #expect(await manager.deviceInfos[identifier]?.physicalDevice == newConnection.physicalDevice)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == newConnection.connectionID)
    #expect(await manager.pipelines[identifier] !== oldPipeline)
    #expect(await manager.hidOutputQueues[identifier] === queue)
    await manager.stop()
  }
}
