import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct UnboundHIDDeviceTests {
  @Test
  func rejectedHIDDeviceIsReportedAndItsClaimReleasedUntilDisconnect() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 90)

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(
      await manager.unboundDeviceDescriptions() == [
        UnboundDeviceSnapshot(
          vendorID: 0x1234,
          productID: 0x5678,
          name: "Test pad",
          connection: "USB",
          accessBackend: .hid,
          reason: .descriptorContractMismatch,
          rejectedCandidates: [],
          interfaces: [ProtocolBindingResult.InterfaceSummary(hostHIDInterface(.usb))]
        )
      ]
    )
    #expect(await backend.releasedLocations() == [90])

    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func rejectedHIDDeviceAtABoundPipelineLocationKeepsTheClaim() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let bound = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91,
      interface: gamepadHIDInterface(host: .usb)
    )
    await manager.handleHIDEvent(.connected(connection: bound, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)

    let rejected = Self.connection(vendorID: 0x045E, productID: 0x02EA, locationID: 91)
    await manager.handleHIDEvent(.connected(connection: rejected, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().count == 1)
    let unbound = await manager.unboundDeviceDescriptions()
    #expect(unbound.map(\.reason) == [.interfaceContractMismatch])
    #expect(await backend.releasedLocations().isEmpty)
    await manager.stop()
  }

  @Test
  func stopClearsUnboundDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 92)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.unboundDeviceDescriptions().count == 1)

    await manager.stop()

    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    #expect(await manager.unboundHIDClaims.isEmpty)
  }

  @Test
  func rejectedSiblingOfOneControllerTracksItsBoundPipeline() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    let rejected = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 95,
      serialNumber: "pad-1"
    )
    await manager.handleHIDEvent(.connected(connection: rejected, ownership: .exclusive))
    #expect(await backend.releasedLocations() == [95])

    let bound = Self.connection(
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91,
      serialNumber: "pad-1",
      interface: gamepadHIDInterface(host: .usb)
    )
    await manager.handleHIDEvent(.connected(connection: bound, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)
    #expect(await backend.reacquiredLocations() == [95])

    await manager.handleHIDEvent(.disconnected(connection: bound))
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await backend.releasedLocations() == [95, 95])
    await manager.stop()
  }

  @Test
  func hidAccessFailureClearsUnboundHIDDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(vendorID: 0x1234, productID: 0x5678, locationID: 93)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    #expect(await manager.unboundDeviceDescriptions().count == 1)

    await manager.handleHIDEvent(.accessFailure(.hostStatus(1)))

    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func unboundDevicesRoundTripThroughTheStatusPayload() throws {
    let device = ApplicationServiceUnboundDevice(
      vendorID: 0x045E,
      productID: 0x02EA,
      name: "Xbox Wireless Controller",
      connection: "USB",
      accessBackend: .hid,
      reason: .ambiguousProtocolMatch,
      rejectedCandidates: [
        .init(
          protocolID: .hidDescriptor,
          reason: .ambiguousProtocolMatch,
          catalogRecordID: "045e-02ea"
        )
      ],
      interfaces: [ProtocolBindingResult.InterfaceSummary(gamepadHIDInterface(host: .usb))]
    )
    let payload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      unboundDevices: [device]
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceStatusPayload.self,
      from: JSONEncoder().encode(payload)
    )
    #expect(decoded.unboundDevices == [device])
  }

  private static func connection(
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32,
    serialNumber: String? = nil,
    interface: PhysicalInterfaceSignature = hostHIDInterface(.usb)
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        productName: "Test pad",
        serialNumber: serialNumber,
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [interface]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
