import IOKit
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

struct VirtualHIDExtensionConfigurationTests {
  @Test
  func usbPersonalityUsesOnlyApplesApprovedMicrosoftPairs() throws {
    let configuration = VirtualHIDExtensionConfiguration.xboxUSB
    let usb = try #require(configuration.usbDevice)

    #expect(configuration.bundleIdentifier == "com.openjoystickdriver.VirtualHIDDevice")
    #expect(configuration.personalityName == "XboxUSB")
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

  @Test
  func factoryPersonalityIsResourcesMatchedInTheSameExtension() throws {
    let configuration = VirtualHIDExtensionConfiguration.hidFactory
    let factory = try #require(configuration.hidDeviceFactory)

    #expect(configuration.bundleIdentifier == "com.openjoystickdriver.VirtualHIDDevice")
    #expect(configuration.personalityName == "HIDFactory")
    #expect(configuration.providerClass == "IOUserResources")
    #expect(configuration.matchingProperties == ["IOResourceMatch": .string("IOKit")])
    #expect(configuration.capabilities == .hid)
    #expect(configuration.usbDevice == nil)
    #expect(HIDDeviceFactoryConfiguration.deviceLimit.contains(factory.maximumDevices))
    #expect(factory.maximumDevices == 8)
  }

  @Test
  func eachPersonalityMatchesOnlyItsOwnService() {
    let factory = VirtualHIDExtensionConfiguration.hidFactory.serviceMatch.registryProperties
    let usb = VirtualHIDExtensionConfiguration.xboxUSB.serviceMatch.registryProperties

    #expect(factory["SwifterKitPersonality"] == .string("HIDFactory"))
    #expect(usb["SwifterKitPersonality"] == .string("XboxUSB"))
    #expect(factory["CFBundleIdentifier"] == usb["CFBundleIdentifier"])
  }

  @Test
  func usbPersonalityCanBeLeftOut() {
    let full = VirtualHIDExtensionConfiguration.driverExtension()
    let factoryOnly = VirtualHIDExtensionConfiguration.driverExtension(includingUSB: false)

    #expect(Set(full.personalities.keys) == ["HIDFactory", "XboxUSB"])
    #expect(Array(factoryOnly.personalities.keys) == ["HIDFactory"])
    #expect(factoryOnly.bundleIdentifier == full.bundleIdentifier)
  }

  @Test
  func registryServiceBecomesStableKitOwnedDeviceValue() throws {
    let service = DriverService(
      id: 42,
      name: "XboxUSB",
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
          route: .usbDriverKit,
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
    #expect(observation.serviceIdentity == device.serviceIdentity)
    #expect(observation.physicalLocationIdentifier == 77)
    #expect(observation.deviceRelease == nil)
    #expect(observation.configurationValue == nil)
    #expect(
      observation.interfaces == [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbDriverKit,
          usbRoute: .usbDriverKit
        )
      ]
    )
  }

  @Test
  func driverKitObservationKeepsUnavailableFactsNil() throws {
    let service = DriverService(
      id: 42,
      name: "XboxUSB",
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
          serviceIdentity: USBTransportServiceIdentity(route: .usbDriverKit, serviceID: 42),
          vendorID: 0x3537,
          productID: 0x1010,
          productName: "GameSir G7 SE",
          interfaces: [
            PhysicalInterfaceSignature(
              hostTransport: .usb,
              accessBackend: .usbDriverKit,
              usbRoute: .usbDriverKit
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
      ) == .accessDenied
    )
    #expect(
      USBDriverKitTransportProvider.transportError(
        DriverKitError(kind: .serviceUnavailable, operation: "discover")
      ) == .disconnected
    )
  }
}
