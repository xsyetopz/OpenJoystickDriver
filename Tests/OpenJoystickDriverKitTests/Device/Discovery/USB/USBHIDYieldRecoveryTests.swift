import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A raw-USB service the host refuses to open.
private actor OpenRefusingProvider: USBTransportProvider {
  let device: USBTransportDevice
  let observation: PhysicalDevice

  init(device: USBTransportDevice, observation: PhysicalDevice) {
    self.device = device
    self.observation = observation
  }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { observation }

  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) -> PhysicalDevice? { observation }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws -> any USBTransportSession { throw USBTransportError.accessDenied }
}

/// A HID route that yielded to raw USB comes back when the raw-USB pipeline never starts.
struct USBHIDYieldRecoveryTests {
  private let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 92,
    vendorID: 0x1234,
    productID: 0x5678,
    locationID: 93
  )

  private var observation: PhysicalDevice {
    PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
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
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
          ]
        )
      ]
    )
  }

  @Test
  func refusedRawUSBOpenReadmitsTheYieldedHIDConnection() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = OpenRefusingProvider(device: device, observation: observation)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    let hid = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: device.vendorID,
        productID: device.productID,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: 93,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingLocationID: 93
    )
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))
    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) != .retry)

    var sources: [DeviceDiscoverySource] = []
    for _ in 0..<200 {
      await manager.restoreYieldedHIDRoutes()
      sources = await manager.connectedDeviceDescriptions().map(\.discoverySource)
      if sources == [.hid] { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(sources == [.hid])
    #expect(await backend.releasedLocations() == [93])
    #expect(await backend.reacquiredLocations() == [93])
    await manager.stop()
  }
}
