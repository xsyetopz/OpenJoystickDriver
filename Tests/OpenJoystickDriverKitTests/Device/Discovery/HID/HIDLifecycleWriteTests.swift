import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Lifecycle writes (startup, activation, recovery) are best-effort: one failed report neither
/// stops the reports after it nor skips recovery expiry, and they bypass the user-output rate
/// limit.
struct HIDLifecycleWriteTests {
  struct Started {
    let backend: ScriptedHIDAccessBackend
    let manager: DeviceManager
  }

  /// Connects one catalog HID controller and runs its startup path to the end.
  func start(
    vendorID: UInt16,
    productID: UInt16,
    transport: String,
    host: PhysicalTransport,
    locationID: UInt32,
    rejecting rejected: [PhysicalHIDOutputReport]
  ) async -> Started {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    for report in rejected { await backend.reject(report) }
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        productName: "Lifecycle controller",
        transportProperty: transport,
        physicalLocationIdentifier: locationID,
        // A Steam Controller binds only its feature-report gamepad interface.
        interfaces: [
          vendorID == 0x28DE ? steamHIDInterface(number: 2) : gamepadHIDInterface(host: host)
        ]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    return Started(backend: backend, manager: manager)
  }

  @Test
  func failedStartupReportStillSendsTheLaterOnesAtThePlanInterval() async throws {
    let startup = Switch1Driver().startupWrites().hidOutputs
    // The description's handshake commands go first; the driver adds the counter-stamped reports.
    let declared = PhysicalProtocolID.nintendoSwitch1.protocolDescription.startupWrites(
      phase: .startup,
      variant: .usb,
      parameters: ProtocolParameters(layout: .pro)
    ).map(\.write).hidOutputs
    let started = await start(
      vendorID: 0x057E,
      productID: 0x2009,
      transport: "USB",
      host: .usb,
      locationID: 301,
      rejecting: [startup[1]]
    )
    let sent = await started.backend.recordedOutputReports()
    #expect(
      Array(sent.prefix(declared.count + startup.count - 1))
        == declared + startup.enumerated().filter { $0.0 != 1 }.map(\.1)
    )
    // Startup is paced by the plan's 20 ms, not the 50 ms user-output rate limit, which would
    // also stamp the last physical output time and delay the first rumble.
    let identifier = try #require(await started.manager.connectedLogicalControllerIDs().first)
    let pipeline = try #require(await started.manager.pipelines[identifier])
    #expect(await pipeline.sessionPlan().hidStartupIntervalNanoseconds == 20_000_000)
    #expect(await pipeline.minimumPhysicalOutputIntervalNanoseconds() == 50_000_000)
    #expect(await started.manager.lastPhysicalHIDOutputNanoseconds[identifier] == nil)
    await started.manager.stop()
  }

  @Test
  func failedFeatureReportStillSendsTheRest() async {
    let activation = SteamControllerDriver().activationWrites().hidFeatures
    let started = await start(
      vendorID: 0x28DE,
      productID: 0x1102,
      transport: "USB",
      host: .usb,
      locationID: 302,
      rejecting: [activation[0]]
    )
    #expect(await started.backend.recordedFeatureReports() == Array(activation.dropFirst()))
    await started.manager.stop()
  }

  @Test
  func failedRecoveryWriteStillExpiresRecovery() async throws {
    let parser = Switch1Driver(isBluetooth: true)
    _ = parser.startupWrites()
    let firstRecovery = try #require(parser.startupRecoveryWrites().hidOutputs.first)
    let started = await start(
      vendorID: 0x057E,
      productID: 0x2009,
      transport: "Bluetooth",
      host: .bluetoothClassic,
      locationID: 303,
      rejecting: [firstRecovery]
    )
    let identifier = try #require(await started.manager.connectedLogicalControllerIDs().first)
    let pipeline = try #require(await started.manager.pipelines[identifier])
    #expect(await pipeline.isActive)
    #expect(await pipeline.hidStartupRecoveryWrites().isEmpty)
    await started.manager.stop()
  }
}
