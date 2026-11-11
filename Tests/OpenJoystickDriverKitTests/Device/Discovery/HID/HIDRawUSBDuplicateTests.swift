import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A controller served over raw USB must not gain a second pipeline through one of its HID
/// interfaces.
struct HIDRawUSBDuplicateTests {
  @Test
  func cataloguedRawUSBRowObservedOverHIDStaysUnboundWhileItsPipelineRuns() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = USBDiscoveryRecordingProvider(devices: [device])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    guard case .claimed = await manager.handleUSBDeviceAdded(device, provider: provider) else {
      Issue.record("The raw-USB service was not claimed")
      return
    }

    let hid = connection(vendorID: 1_118, productID: 721, locationID: 9)
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().map(\.discoverySource) == [.rawUSB])
    #expect(
      await manager.unboundDeviceDescriptions().map(\.reason) == [.unsupportedTransportVariant]
    )
    // The catalog row that matched names the rejected family.
    let rejected = await manager.unboundDeviceDescriptions().first?.bindingResult.rejectedCandidates
    #expect(
      rejected == [
        .init(
          protocolID: .xboxGIP,
          reason: .unsupportedTransportVariant,
          catalogRecordID: "045e-02d1"
        )
      ]
    )
    #expect(await backend.releasedLocations().isEmpty)
    await manager.stop()
  }

  @Test
  func signatureBoundDeviceKeepsItsHIDInterfaceUnbound() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 90,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91
    )
    // The registry publishes the GIP triple; the configuration descriptor adds its endpoints.
    func observation(_ endpoints: [PhysicalEndpointSignature]?) -> PhysicalDevice {
      PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: endpoints
          )
        ]
      )
    }
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: observation(nil),
      configured: observation([
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
      ])
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    guard case .claimed = await manager.handleUSBDeviceAdded(device, provider: provider) else {
      Issue.record("The raw-USB service was not claimed")
      return
    }

    // A serial-less HID gamepad interface at the same location passes `HIDDescriptor` alone.
    let hid = connection(vendorID: 0x1234, productID: 0x5678, locationID: 91)
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().map(\.discoverySource) == [.rawUSB])
    let unbound = await manager.unboundDeviceDescriptions()
    #expect(unbound.map(\.reason) == [.ambiguousProtocolMatch])
    // Only the HID-side family is rejected; the raw-USB family is bound on its own pipeline.
    #expect(
      unbound.first?.bindingResult.rejectedCandidates == [
        .init(protocolID: .hidDescriptor, reason: .ambiguousProtocolMatch)
      ]
    )
    #expect(await backend.releasedLocations().isEmpty)
    await manager.stop()
  }

  private func connection(
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
