import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverRelay

struct ConfigurationTests {
  @Test func configurationConsumesInwardRelayIdentity() throws {
    let configuration = OpenJoystickDriverRelayConfiguration.driver
    let hid = try #require(configuration.hidDevice)

    #expect(configuration.bundleIdentifier == DriverKitRelayIdentity.bundleIdentifier)
    #expect(configuration.providerClass == "IOUserResources")
    #expect(configuration.matchingProperties == ["IOResourceMatch": .string("IOKit")])
    #expect(configuration.capabilities == .hid)
    #expect(
      configuration.serviceMatch.registryProperties["IOUserClass"]
        == .string("SwifterKitRuntimeService")
    )
    #expect(hid.reportDescriptor == DriverKitRelayIdentity.reportDescriptor)
    #expect(hid.transport == DriverKitRelayIdentity.transport)
    #expect(hid.vendorID == DriverKitRelayIdentity.vendorID)
    #expect(hid.productID == DriverKitRelayIdentity.productID)
    #expect(hid.versionNumber == DriverKitRelayIdentity.versionNumber)
    #expect(hid.locationID == DriverKitRelayIdentity.locationID)
    #expect(hid.manufacturer == DriverKitRelayIdentity.manufacturer)
    #expect(hid.product == DriverKitRelayIdentity.product)
    #expect(hid.serialNumber == DriverKitRelayIdentity.serialNumber)
    #expect(hid.primaryUsagePage == DriverKitRelayIdentity.primaryUsagePage)
    #expect(hid.primaryUsage == DriverKitRelayIdentity.primaryUsage)
    #expect(hid.acceptedHostReportTypes == .output)
    #expect(
      DriverKitRelayIdentity.matches(
        runtimeClass: DriverKitRelayIdentity.runtimeServiceClass,
        transport: hid.transport,
        vendorID: hid.vendorID,
        productID: hid.productID,
        versionNumber: hid.versionNumber,
        locationID: hid.locationID,
        manufacturer: hid.manufacturer,
        product: hid.product,
        serialNumber: hid.serialNumber,
        primaryUsagePage: hid.primaryUsagePage,
        primaryUsage: hid.primaryUsage
      )
    )
  }

  @Test func profileAndDiagnosticsIdentityShareExactRelevantValues() {
    #expect(UInt32(VirtualDeviceProfile.default.vendorID) == DriverKitRelayIdentity.vendorID)
    #expect(UInt32(VirtualDeviceProfile.default.productID) == DriverKitRelayIdentity.productID)
    #expect(
      UInt32(VirtualDeviceProfile.default.versionNumber) == DriverKitRelayIdentity.versionNumber
    )
    #expect(VirtualDeviceProfile.default.manufacturer == DriverKitRelayIdentity.manufacturer)
    #expect(DriverKitRelayIdentity.bundleIdentifier == "com.openjoystickdriver.VirtualHIDDevice")
    #expect(DriverKitRelayIdentity.locationID == 0x4F4A_4401)
    #expect(DriverKitRelayIdentity.product == "OpenJoystickDriver DriverKit Relay")
    #expect(DriverKitRelayIdentity.serialNumber == "OpenJoystickDriver-DriverKit")
  }

  @Test func descriptorDeclaresSymmetricFifteenByteReports() {
    #expect(DriverKitRelayIdentity.reportSize == 15)
    #expect(
      DriverKitRelayIdentity.reportDescriptor == [
        0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95,
        0x0F, 0x09, 0x02, 0x91, 0x02, 0x09, 0x03, 0x81, 0x02, 0xC0,
      ]
    )
  }
}
