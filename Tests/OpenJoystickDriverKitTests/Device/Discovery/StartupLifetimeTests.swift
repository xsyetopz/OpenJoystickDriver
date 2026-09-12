import Testing

@testable import OpenJoystickDriverKit

struct StartupLifetimeTests {
  @Test func stoppedAndReplacedPipelinesCannotContinueStartup() async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678, locationID: 81)
    let connected = HIDDeviceEvent.connected(
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      serialNumber: nil,
      locationID: 81,
      productName: "Startup test",
      transport: "USB",
      ownership: .exclusive
    )
    await manager.handleHIDEvent(connected)
    let original = try #require(await manager.pipelines[identifier])
    #expect(await manager.isCurrentHIDStartupPipeline(original))
    await manager.handleHIDEvent(
      .ownershipChanged(locationID: 81, ownership: .ownedByAnotherClient)
    )
    #expect(await manager.isCurrentHIDStartupPipeline(original) == false)
    await manager.handleHIDEvent(.ownershipChanged(locationID: 81, ownership: .exclusive))
    let replacement = try #require(await manager.pipelines[identifier])
    #expect(replacement !== original)
    // Even restarting the stale actor must not authorize its delayed reports on the new device.
    await original.start()
    #expect(await manager.isCurrentHIDStartupPipeline(original) == false)
    #expect(await manager.isCurrentHIDStartupPipeline(replacement))
    await original.stop()
    await manager.stop()
    #expect(await manager.isCurrentHIDStartupPipeline(replacement) == false)
  }

  @Test func startupPlanRequiresAnActivePipeline() async {
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 0x057E, productID: 0x2009),
      transport: .hid(locationID: 82),
      parser: SwitchProParser(),
      dispatcher: LoggingOutputDispatcher()
    )
    #expect(await pipeline.hidStartupOutputPlan(transport: "Bluetooth").0.isEmpty)
    await pipeline.start()
    let (reports, interval) = await pipeline.hidStartupOutputPlan(transport: "Bluetooth")
    #expect(reports.count == 5)
    #expect(interval == 60_000_000)
    #expect(await pipeline.hidStartupOutputPlan(transport: nil).0.isEmpty)
    await pipeline.stop()
    #expect(await pipeline.hidStartupOutputPlan(transport: "Bluetooth").0.isEmpty)
  }

  @Test func featureReadsDispatchTransportThroughTheProtocol() {
    let provider: any HIDStartupFeatureReadRequestProvider = DS4Parser()
    #expect(provider.hidStartupFeatureReadRequests(transport: "Bluetooth").map(\.reportID)
      == [2, 5])
    #expect(provider.hidStartupFeatureReadRequests(transport: "USB").map(\.reportID) == [2])
  }
}
