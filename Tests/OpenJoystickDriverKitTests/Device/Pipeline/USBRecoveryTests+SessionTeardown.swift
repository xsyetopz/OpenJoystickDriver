import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension USBPipelineRecoveryTests {
  @Test
  func manualSuspensionPersistsAcrossSleepUntilResume() async throws {
    let sessions = (0..<4).map { _ in RecoveryUSBSession(readError: .timeout) }
    let provider = RecoveryUSBProvider(sessions: sessions, devices: [device])
    let dispatcher = RecoveryOutputDispatcher()
    let manager = makeManager(using: provider, dispatcher: dispatcher)
    await manager.start()
    await waitUntil("sessions[0].writeCount > 0") { await sessions[0].writeCount > 0 }
    let suspended = await manager.suspendController(.model(identifier.model))
    #expect(suspended.state == .suspended)

    // Two cycles: the intent must survive a sleep during which the controller stayed suspended.
    for _ in 1...2 {
      await manager.systemWillSleep()
      let presenceBeforeWake = dispatcher.presenceCount
      await manager.systemDidWake()
      await waitUntil("manager.pipelines[identifier] != nil") {
        await manager.pipelines[identifier] != nil
      }
      #expect(await provider.openCount == 1)
      let pipeline = try #require(await manager.pipelines[identifier])
      #expect(await pipeline.controllerSessionState() == .suspended)
      #expect(dispatcher.presenceCount == presenceBeforeWake)
    }

    let resumed = await manager.resumeController(.model(identifier.model))
    #expect(resumed.state == .active)
    await manager.systemWillSleep()
    await manager.systemDidWake()
    await waitUntil("sessions[2].writeCount > 0") { await sessions[2].writeCount > 0 }
    let pipeline = try #require(await manager.pipelines[identifier])
    #expect(await pipeline.controllerSessionState() == .active)
    await manager.stop()
    #expect(await manager.suspendedControllerIdentities.isEmpty)
  }

  /// Admission publishes a pipeline before it starts it, so a detach can stop it first.
  ///
  /// The late start must not open a session that no later stop would close.
  @Test
  func startAfterStopOpensNothing() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [session])
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryInputParser(),
      dispatcher: RecoveryOutputDispatcher(),
      usbTransportProvider: provider
    )

    await pipeline.stop()
    await pipeline.start()
    await pipeline.usbRunTaskForTesting()?.value

    #expect(await provider.openCount == 0)
    #expect(await !pipeline.isActive)
    await pipeline.stop()
  }

  @Test
  func invalidatedSessionRejectsLateRumble() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryRumbleParser(),
      dispatcher: RecoveryOutputDispatcher()
    )
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)

    await pipeline.invalidateUSBHandle(session)

    #expect(!(await pipeline.sendUSBOutput(RecoveryRumbleParser().rumblePackets(1, 2, 3, 4))))
    #expect(await session.writeCount == 0)
    #expect(await session.closeCount == 1)
  }

  @Test
  func physicalDisconnectEndsManualSuspension() async throws {
    let sessions = (0..<2).map { _ in RecoveryUSBSession(readError: .timeout) }
    let provider = RecoveryUSBProvider(sessions: sessions, devices: [device])
    let manager = makeManager(using: provider)
    await manager.start()
    await waitUntil("sessions[0].writeCount > 0") { await sessions[0].writeCount > 0 }
    let suspended = await manager.suspendController(.model(identifier.model))
    #expect(suspended.state == .suspended)

    await provider.setDevices([])
    await waitUntil("manager.pipelines.isEmpty") { await manager.pipelines.isEmpty }
    #expect(await manager.suspendedControllerIdentities.isEmpty)
    await provider.setDevices([device])
    await waitUntil("sessions[1].writeCount > 0") { await sessions[1].writeCount > 0 }
    let pipeline = try #require(await manager.pipelines[identifier])
    #expect(await pipeline.controllerSessionState() == .active)
    await manager.stop()
  }

  @Test
  func teardownStartedPipelineWritesOnlyTeardownScopedOutput() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryRumbleParser(),
      dispatcher: RecoveryOutputDispatcher()
    )
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)

    await pipeline.acceptOnlyTeardownOutput()

    #expect(!(await pipeline.sendUSBOutput(RecoveryRumbleParser().rumblePackets(1, 2, 3, 4))))
    #expect(await session.writeCount == 0)
    let teardownWrite = await ControllerTeardownOutput.$isActive.withValue(true) {
      await pipeline.sendUSBOutput(RecoveryRumbleParser().rumblePackets(0, 0, 0, 0))
    }
    #expect(teardownWrite)
    #expect(await session.writeCount == 1)
  }

  @Test
  func shutdownNeutralizesAllUSBMotorsWithOneCombinedReport() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let parser = RecoveryRumbleParser()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: parser,
      dispatcher: RecoveryOutputDispatcher()
    )
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)
    let manager = DeviceManager(
      dispatcher: RecoveryOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )

    await manager.neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)

    #expect(await session.writes == [[0, 0, 0, 0]])
  }

  @Test
  func physicalRemovalDiscardsOwnershipWithoutWritingToAbsentDevice() async {
    let session = RecoveryUSBSession(readError: .timeout)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryRumbleParser(),
      dispatcher: RecoveryOutputDispatcher()
    )
    await pipeline.setUSBHandleForTesting(session)
    let manager = DeviceManager(
      dispatcher: RecoveryOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let owner = UUID()
    _ = await manager.setPhysicalOutputForTesting(
      .rumble(motor: .lowFrequency, intensity: 1),
      owner: owner,
      identifier: identifier
    )

    await manager.discardPhysicalOutputs(for: identifier)

    #expect(await session.writeCount == 0)
    #expect(await manager.mappingClaimCountForTesting == 0)
  }

  @Test
  func controllerRecordReloadReadmitsConnectedControllers() async {
    let first = RecoveryUSBSession(readError: .timeout)
    let second = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [first, second], devices: [device])
    let manager = makeManager(using: provider)
    await manager.reloadControllerRecords(changing: [identifier.model])
    #expect(await manager.detectionTasks.isEmpty)

    await manager.start()
    await waitUntil("first.writeCount > 0") { await first.writeCount > 0 }
    await manager.reloadControllerRecords(changing: [identifier.model])
    #expect(await first.closeCount == 1)
    await waitUntil("second.writeCount > 0") { await second.writeCount > 0 }
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    #expect(await provider.openedDevices == [device, device])
    await manager.stop()
  }

  @Test
  func controllerRecordReloadReadmitsOnlyChangedModelAndKeepsItsSuspension() async throws {
    let other = USBTransportDevice(
      route: .rawUSB,
      serviceID: 2,
      vendorID: 0x3537,
      productID: 0x1022,
      locationID: 8
    )
    let sessions = (0..<3).map { _ in RecoveryUSBSession(readError: .timeout) }
    let provider = RecoveryUSBProvider(sessions: sessions, devices: [device, other])
    let manager = makeManager(using: provider)
    await manager.start()
    await waitUntil("provider.openCount == 2") { await provider.openCount == 2 }
    let suspended = await manager.suspendController(.model(identifier.model))
    #expect(suspended.state == .suspended)
    let opened = await provider.openedDevices
    let changedSession = sessions[try #require(opened.firstIndex(of: device))]
    let otherSession = sessions[try #require(opened.firstIndex(of: other))]

    let before = try #require(await manager.pipelines[identifier])
    await manager.reloadControllerRecords(changing: [identifier.model])
    await waitUntil("pipeline readmitted") {
      guard let current = await manager.pipelines[identifier] else { return false }
      return current !== before
    }
    #expect(await changedSession.closeCount == 1)
    #expect(await otherSession.closeCount == 0)
    #expect(await provider.openCount == 2)
    let pipeline = try #require(await manager.pipelines[identifier])
    #expect(await pipeline.controllerSessionState() == .suspended)
    await manager.stop()
  }

  @Test
  func controllerRecordReloadKeepsControllersWhoseRecordDidNotChange() async {
    let first = RecoveryUSBSession(readError: .timeout)
    let second = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [first, second], devices: [device])
    let manager = makeManager(using: provider)
    await manager.start()
    await waitUntil("first.writeCount > 0") { await first.writeCount > 0 }

    await manager.reloadControllerRecords(changing: [
      ControllerModelID(vendorID: 0x1234, productID: 0xabcd)
    ])
    #expect(await first.closeCount == 0)
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    #expect(await provider.openedDevices == [device])
    await manager.stop()
  }
}
