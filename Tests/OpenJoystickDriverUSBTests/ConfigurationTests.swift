import IOKit
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

struct USBDriverKitExtensionConfigurationTests {
  @Test
  func productionConfigurationUsesOnlyApplesApprovedMicrosoftPairs() throws {
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
    let match = configuration.serviceMatch.registryProperties
    #expect(match["IOUserClass"] == .string("SwifterKitRuntimeService"))
    #expect(match["CFBundleIdentifier"] == .string("com.openjoystickdriver.XboxUSBDevice"))
  }

  @Test
  func bundledRecordsMarkExactlyAppleHeldModels() {
    let held = USBDriverKitExtensionConfiguration.appleHeldModels(in: ControllerRecordSet.bundled)

    #expect(
      held == [0x02EA, 0x0B00, 0x0B12].map { ControllerModelID(vendorID: 0x045E, productID: $0) }
    )
    #expect(OpenJoystickDriverUSBTransportProvider.driverKitRequiredModels == Set(held))
  }

  @Test
  func matchListComesFromExtensionOwnedRecordsWithinGrant() {
    let outside = ControllerModelID(vendorID: 0x045E, productID: 0x02FF)
    let otherVendor = ControllerModelID(vendorID: 0x0E6F, productID: 0x02D1)
    let models =
      [0x0B12, 0x02D1].map { ControllerModelID(vendorID: 0x045E, productID: $0) }
      + [outside, otherVendor]

    #expect(
      USBDriverKitExtensionConfiguration.matchedProductIDs(extensionOwned: models) == [
        0x02D1, 0x0B12,
      ]
    )
    #expect(
      USBDriverKitExtensionConfiguration.modelsOutsideGrant(extensionOwned: models)
        == [
          otherVendor, outside,
        ].sorted()
    )
  }

  @Test
  func bundledRecordsStayWithinGrant() {
    let models = USBDriverKitExtensionConfiguration.extensionOwnedModels(
      in: ControllerRecordSet.bundled
    )
    #expect(USBDriverKitExtensionConfiguration.modelsOutsideGrant(extensionOwned: models).isEmpty)
  }

  @Test
  func registryServiceBecomesStableKitOwnedDeviceValue() throws {
    let service = DriverService(
      id: 42,
      name: "XboxUSBDevice",
      properties: [
        "idVendor": .unsignedInteger(0x3537), "idProduct": .integer(0x1010),
        "locationID": .unsignedInteger(77), "USB Product Name": .string("GameSir G7 SE"),
        "USB Serial Number": .string("serial"),
      ]
    )

    let device = try #require(USBDriverKitTransportProvider.device(service))
    #expect(
      device
        == USBTransportDevice(
          route: .usbExtension,
          serviceID: 42,
          vendorID: 0x3537,
          productID: 0x1010,
          locationID: 77,
          observedPhysicalLocationIdentifier: 77,
          productName: "GameSir G7 SE",
          serialNumber: "serial"
        )
    )
    #expect(device.observedPhysicalLocationIdentifier == 77)
    let observation = try #require(
      USBDriverKitTransportProvider.physicalDeviceObservation(from: service)
    )
    #expect(observation.serviceAddress == device.serviceAddress)
    #expect(observation.physicalLocationIdentifier == 77)
    #expect(observation.deviceRelease == nil)
    #expect(observation.configurationValue == nil)
    #expect(
      observation.interfaces == [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbExtension,
          usbRoute: .usbExtension
        )
      ]
    )
  }

  @Test
  func driverKitObservationKeepsUnavailableFactsNil() throws {
    let service = DriverService(
      id: 42,
      name: "XboxUSBDevice",
      properties: [
        "idVendor": .unsignedInteger(0x3537), "idProduct": .integer(0x1010),
        "USB Product Name": .string("GameSir G7 SE"),
      ]
    )

    let device = try #require(USBDriverKitTransportProvider.device(service))
    #expect(device.locationID == UInt32(truncatingIfNeeded: service.id))
    #expect(device.observedPhysicalLocationIdentifier == nil)

    let observation = try #require(
      USBDriverKitTransportProvider.physicalDeviceObservation(from: service)
    )
    #expect(
      observation
        == PhysicalDevice(
          serviceAddress: ControllerConnectionAddress.usbService(
            route: .usbExtension,
            serviceID: 42
          ),
          vendorID: 0x3537,
          productID: 0x1010,
          productName: "GameSir G7 SE",
          interfaces: [
            PhysicalInterfaceSignature(
              hostTransport: .usb,
              accessBackend: .usbExtension,
              usbRoute: .usbExtension
            )
          ]
        )
    )
  }

  @Test
  func driverKitFailuresMapToStableTransportCategories() {
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnTimeout), operation: "read")
      ) == .timeout
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnExclusiveAccess), operation: "open")
      ) == .ownedByAnotherClient(owner: nil)
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnNotPermitted), operation: "open")
      ) == .accessDenied
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .ioReturn(kIOReturnNotPrivileged), operation: "open")
      ) == .accessDenied
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .serviceUnavailable, operation: "discover")
      ) == .disconnected
    )
  }
}
