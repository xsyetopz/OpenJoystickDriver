import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension StartupLifetimeTests {
  /// Without raw-USB detection, a record reload re-admits each tracked HID connection of the
  /// changed model at once. The GameSir connections are synthetic, as in `HIDLocationRoutingTests`.
  @Test
  func controllerRecordReloadReadmitsOnlyTrackedHIDConnectionsOfTheChangedModel() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: HIDRoleEventRecorder(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let changed = Self.gameSir(productID: 0x100B, locationID: 0x0021_0000)
    let other = Self.gameSir(productID: 0x1053, locationID: 0x0022_0000)
    // OJD never received this connection, so the reload must not admit it.
    let untracked = Self.gameSir(productID: 0x100B, locationID: 0x0023_0000)
    await backend.setConnectionSnapshots(
      [changed, other, untracked].map {
        HIDDeviceConnectionSnapshot(connection: $0, ownership: .exclusive)
      }
    )
    await manager.handleHIDEvent(.connected(connection: changed, ownership: .exclusive))
    await manager.handleHIDEvent(.connected(connection: other, ownership: .exclusive))
    let changedID = DeviceIdentifier(vendorID: 0x3537, productID: 0x100B, locationID: 0x0021_0000)
    let otherID = DeviceIdentifier(vendorID: 0x3537, productID: 0x1053, locationID: 0x0022_0000)
    let changedPipeline = try #require(await manager.pipelines[changedID])
    let otherPipeline = try #require(await manager.pipelines[otherID])

    await manager.reloadControllerRecords(
      changing: [ControllerIdentity(vendorID: 0x3537, productID: 0x100B)]
    )
    try await Self.waitForHIDInitializations(of: manager)

    #expect(Set(await manager.pipelines.keys) == [changedID, otherID])
    #expect(try #require(await manager.pipelines[changedID]) !== changedPipeline)
    #expect(try #require(await manager.pipelines[otherID]) === otherPipeline)
    #expect(await manager.deviceInfos[changedID]?.hidConnectionID == changed.connectionID)
    await manager.stop()
  }

  private static func waitForHIDInitializations(of manager: DeviceManager) async throws {
    for _ in 0..<400 where await !manager.hidInitializationTasks.isEmpty {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await manager.hidInitializationTasks.isEmpty)
  }

  private static func gameSir(productID: UInt16, locationID: UInt32) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: productID,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            hostTransport: .usb,
            accessBackend: .ioHID,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ]
      ),
      routingLocationID: locationID
    )
  }
}
