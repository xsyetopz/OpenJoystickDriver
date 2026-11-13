import Foundation
import IOKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private actor DeferredPowerEventInvocationGate {
  private var isPaused = false
  private var isReleased = false
  private var pauseContinuation: CheckedContinuation<Void, Never>?
  private var reachedContinuation: CheckedContinuation<Void, Never>?

  func pauseUntilReleased() async {
    isPaused = true
    reachedContinuation?.resume()
    reachedContinuation = nil
    guard !isReleased else { return }
    await withCheckedContinuation { pauseContinuation = $0 }
  }

  func waitUntilPaused() async {
    guard !isPaused else { return }
    await withCheckedContinuation { reachedContinuation = $0 }
  }

  func release() {
    isReleased = true
    pauseContinuation?.resume()
    pauseContinuation = nil
  }
}

private final class WirelessDisconnectProbe: WirelessControllerDisconnecting, @unchecked Sendable {
  private let lock = NSLock()
  private let outcome: WirelessControllerDisconnectOutcome
  private var addresses: [String] = []

  init(outcome: WirelessControllerDisconnectOutcome) { self.outcome = outcome }

  func disconnect(
    address: String,
    timeoutNanoseconds _: UInt64
  ) async -> WirelessControllerDisconnectOutcome {
    await Task.yield()
    lock.withLock { addresses.append(address) }
    return outcome
  }

  var calls: [String] { lock.withLock { addresses } }
}

private final class AbsoluteStickParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan(inputReportLivenessTimeoutNanoseconds: 1_000_000_000)
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Each report carries the full right stick; report 1 pushes it right, any other centers it.
  func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    ControllerEvent(data.first == 1 ? [.rightStick(x: 1, y: 0)] : [], at: receivedAt.nanoseconds)
  }
}

@Suite(.timeLimit(.minutes(2)))
struct ControllerSessionTests {
  @Test
  func absoluteSnapshotsCenterStickWithoutReleaseDelta() async {
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1, productID: 2),
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: AbsoluteStickParser(),
      dispatcher: output,
      uptimeNanoseconds: ManualUptime().now
    )
    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    #expect(output.snapshot().states == [snapshot(.rightStick(x: 1, y: 0)), .neutral])
    await pipeline.stop()
  }

  @Test(arguments: [
    (WirelessControllerDisconnectOutcome.disconnected, nil as WirelessControllerDisconnectFailure?),
    (
      WirelessControllerDisconnectOutcome.failed(kIOReturnError),
      WirelessControllerDisconnectFailure.disconnectFailed
    ), (WirelessControllerDisconnectOutcome.timedOut, WirelessControllerDisconnectFailure.timedOut),
  ])
  func wirelessDisconnectSuspendsBeforeReturning(
    outcome: WirelessControllerDisconnectOutcome,
    expectedFailure: WirelessControllerDisconnectFailure?
  ) async throws {
    let probe = WirelessDisconnectProbe(outcome: outcome)
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      wirelessControllerDisconnector: probe
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Wireless Controller",
            serialNumber: "aa-bb-cc-dd-ee-ff",
            transportProperty: "Bluetooth",
            physicalLocationIdentifier: 71,
            interfaces: [hostHIDInterface(.bluetoothClassic)]
          ),
          routingAddress: .ioKit(locationID: 71, interfaceNumber: nil),
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    let result = await manager.disconnectWirelessController(.session(device.sessionToken))

    #expect(result.state == (expectedFailure == nil ? .suspended : .active))

    #expect(result.failure == expectedFailure)
    switch outcome {
    case .failed(let code):
      #expect(result.failedStage == .closeBluetoothConnection)
      #expect(result.systemCode == code)
      #expect(result.detail?.contains(String(code)) == true)
    case .timedOut:
      #expect(result.failedStage == .confirmBluetoothDisconnection)
      #expect(result.recovery != nil)
    case .disconnected, .stillConnected: break
    }
    #expect(probe.calls == ["AA:BB:CC:DD:EE:FF"])
    await manager.stop()
  }

  @Test(arguments: [
    ("USB", "AA:BB:CC:DD:EE:FF", WirelessControllerDisconnectFailure.notBluetooth),
    ("Bluetooth", nil as String?, WirelessControllerDisconnectFailure.missingAddress),
  ])
  func wirelessDisconnectRejectsInvalidPhysicalSelectionWithoutSuspending(
    connection: String,
    serialNumber: String?,
    expectedFailure: WirelessControllerDisconnectFailure
  ) async throws {
    let probe = WirelessDisconnectProbe(outcome: .disconnected)
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      wirelessControllerDisconnector: probe
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Controller",
            serialNumber: serialNumber,
            transportProperty: connection,
            physicalLocationIdentifier: 72,
            interfaces: [
              hostHIDInterface(testHostTransport(connection))
            ]
          ),
          routingAddress: .ioKit(locationID: 72, interfaceNumber: nil),
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    let result = await manager.disconnectWirelessController(.session(device.sessionToken))

    #expect(result.state == .active)
    #expect(result.failure == expectedFailure)
    #expect(probe.calls.isEmpty)
    await manager.stop()
  }

  @Test
  func wirelessDisconnectRejectsBluetoothLEWithoutSuspending() async throws {
    let probe = WirelessDisconnectProbe(outcome: .disconnected)
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      wirelessControllerDisconnector: probe
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x057E,
            productID: 0x2073,
            productName: "Controller",
            serialNumber: "AA:BB:CC:DD:EE:FF",
            transportProperty: "Bluetooth Low Energy",
            physicalLocationIdentifier: 74,
            interfaces: [gamepadHIDInterface(host: .bluetoothLE)]
          ),
          routingAddress: .ioKit(locationID: 74, interfaceNumber: nil),
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    let result = await manager.disconnectWirelessController(.session(device.sessionToken))

    #expect(device.connectionState?.transport == .bluetoothLE)
    #expect(result.state == .active)
    #expect(result.failure == .bluetoothLEUnsupported)
    #expect(probe.calls.isEmpty)
    await manager.stop()
  }

  @Test
  func suspensionNeutralizesHeldInputAndIgnoresReportsUntilResume() async {
    let identifier = LogicalControllerID(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x28, timestamp: 1))

    #expect(await pipeline.suspendControllerSession())
    #expect(await pipeline.controllerSessionState() == .suspended)
    #expect(await pipeline.inputState().isEffectivelyNeutral)
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x48, timestamp: 2))
    #expect(await pipeline.inputState().isEffectivelyNeutral)

    let suspended = output.snapshot()
    #expect(suspended.stopped == [identifier])
    #expect(suspended.states.last?.pressed.isEmpty == true)

    #expect(await pipeline.resumeControllerSession())
    #expect(await pipeline.controllerSessionState() == .active)
    await pipeline.stop()
  }

  @Test
  func suspendedControllersRemainInInventoryButAreNotVirtualOutputTargets() async throws {
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Controller",
            transportProperty: "USB",
            physicalLocationIdentifier: 73,
            interfaces: [hostHIDInterface(.usb)]
          ),
          routingAddress: .ioKit(locationID: 73, interfaceNumber: nil),
        ),
        ownership: .exclusive
      )
    )
    let device = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(await manager.activeLogicalControllerIDs().count == 1)

    _ = await manager.suspendController(.session(device.sessionToken))

    #expect(await manager.connectedDeviceDescriptions().count == 1)
    #expect(await manager.activeLogicalControllerIDs().isEmpty)
    await manager.stop()
  }

  @Test
  func suspendClosesControllerHIDHandlesAndResumeReopensThem() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Controller",
            transportProperty: "USB",
            physicalLocationIdentifier: 76,
            interfaces: [hostHIDInterface(.usb)]
          ),
          routingAddress: .ioKit(locationID: 76, interfaceNumber: nil),
        ),
        ownership: .exclusive
      )
    )
    await backend.openHandle(at: 76)
    let device = try #require(await manager.connectedDeviceDescriptions().first)

    #expect(await manager.suspendController(.session(device.sessionToken)).failure == nil)
    #expect(!(await backend.hasOpenHandle(at: 76)))

    #expect(await manager.resumeController(.session(device.sessionToken)).failure == nil)
    #expect(await backend.hasOpenHandle(at: 76))
    await manager.stop()
  }

  @Test
  func delayedPowerEventFromStoppedSessionCannotMutateRestartedManager() async {
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: RecoveryHIDBackend())
    )
    let stoppedSession = DeviceManagerSystemPowerEventSession()
    let invocationGate = DeferredPowerEventInvocationGate()
    let delayedSleep = Task {
      await invocationGate.pauseUntilReleased()
      await manager.systemWillSleep(session: stoppedSession)
    }

    await invocationGate.waitUntilPaused()
    await manager.stop()
    stoppedSession.invalidate()
    await manager.start()
    let restartedGeneration = await manager.lifecycleGeneration

    await invocationGate.release()
    await delayedSleep.value
    #expect(!(await manager.isSystemSleeping))
    #expect(await manager.lifecycleGeneration == restartedGeneration)

    let currentSession = DeviceManagerSystemPowerEventSession()
    await manager.systemWillSleep(session: currentSession)
    #expect(await manager.isSystemSleeping)
    await manager.systemDidWake(session: currentSession)
    #expect(!(await manager.isSystemSleeping))

    currentSession.invalidate()
    await manager.stop()
  }
}
