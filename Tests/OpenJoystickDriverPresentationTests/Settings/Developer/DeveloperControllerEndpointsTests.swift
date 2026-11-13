import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct DeveloperControllerEndpointsTests {
  private static func device(connection: String) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2DC8,
      productID: 0x301B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: connection,
      discoverySource: .hid,
      physicalOwnership: .exclusiveHID,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("dev-endpoints")
    )
  }

  @Test(arguments: [("USB", true), ("Bluetooth Low Energy", false), ("Bluetooth", false)])
  func usbEndpointsOnlyForUSBConnection(connection: String, expected: Bool) {
    #expect(Self.device(connection: connection).hasUSBEndpoints == expected)
  }
}
