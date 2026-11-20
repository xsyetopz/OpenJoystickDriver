import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

// The ZD Ultimate Legend `413D:2104` of issue #22 reports `bDeviceClass` 0: the device class
// lives on each interface, and interface 0 is XUSB (255/93/1). Discovery reads the device
// service with no class filter and finds the transport by interface class.
extension TransportFacadeTests {
  private static let legend = IOUSBHostDeviceFacts(
    serviceID: 22,
    vendorID: 0x413D,
    productID: 0x2104,
    locationID: 0x0110_0000,
    productName: "XBOX 360 For Windows",
    serialNumber: nil
  )

  @Test
  func classZeroCompositeDeviceIsSelectedFromItsDeviceService() {
    let devices = IOUSBHostTransportProvider.devices(from: [Self.legend])

    let selected = OpenJoystickDriverUSBTransportProvider.selectDevices(
      direct: devices,
      driverKit: [],
      supportedRawUSBModels: Set(ProtocolDriverRegistry().rawUSBModels),
      requiredDriverKitModels: OpenJoystickDriverUSBTransportProvider.driverKitRequiredModels
    )

    #expect(selected.map(\.serviceID) == [22])
    #expect(selected.first?.route == .rawUSB)
  }

  @Test
  func classZeroCompositeDeviceFindsXUSBOnInterfaceZero() {
    let xusb = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      endpoints: [
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
      ]
    )

    let discovered = USBDescriptorTransportResolver.discover(
      interfaces: [xusb],
      preferredInterface: 0,
      requirePreferredInterface: true
    )

    #expect(discovered?.interfaceNumber == 0)
    #expect(discovered?.inputEndpoint == 0x81)
    #expect(discovered?.outputEndpoint == 0x02)
  }
}
