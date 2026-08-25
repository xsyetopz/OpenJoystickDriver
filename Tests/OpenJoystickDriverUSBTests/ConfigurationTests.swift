import IOKit
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

struct USBDriverKitExtensionConfigurationTests {
  @Test func productionConfigurationUsesOnlyApplesApprovedMicrosoftPairs() throws {
    let configuration = USBDriverKitExtensionConfiguration.driver
    let usb = try #require(configuration.usbDevice)

    #expect(configuration.bundleIdentifier == "com.openjoystickdriver.XboxUSBDevice")
    #expect(configuration.providerClass == "IOUSBHostInterface")
    #expect(configuration.capabilities == .usb)
    #expect(usb.vendorID == 0x045E)
    #expect(usb.productIDs == [0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12])
    #expect(configuration.matchingProperties["bInterfaceNumber"] == .unsignedInteger(0))
    #expect(configuration.matchingProperties["bInterfaceClass"] == .unsignedInteger(0xFF))
    #expect(configuration.matchingProperties["bConfigurationValue"] == .unsignedInteger(1))
    #expect(configuration.matchingProperties["bInterfaceSubClass"] == .unsignedInteger(0x47))
    #expect(configuration.matchingProperties["bInterfaceProtocol"] == .unsignedInteger(0xD0))
  }

  @Test func registryServiceBecomesStableKitOwnedDeviceValue() throws {
    let service = DriverService(
      id: 42,
      name: "XboxUSBDevice",
      properties: [
        "idVendor": .unsignedInteger(0x3537), "idProduct": .integer(0x1010),
        "locationID": .unsignedInteger(77), "USB Product Name": .string("GameSir G7 SE"),
        "USB Serial Number": .string("serial")
      ]
    )

    let device = try #require(USBDriverKitTransportProvider.device(service))
    #expect(
      device
        == USBTransportDevice(
          route: .usbDriverKit,
          serviceID: 42,
          vendorID: 0x3537,
          productID: 0x1010,
          locationID: 77,
          productName: "GameSir G7 SE",
          serialNumber: "serial"
        )
    )
  }

  @Test func driverKitFailuresMapToStableTransportCategories() {
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnTimeout), operation: "read")
      ) == .timeout
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnExclusiveAccess), operation: "open")
      ) == .accessDenied
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .serviceUnavailable, operation: "discover")
      ) == .disconnected
    )
  }
}
