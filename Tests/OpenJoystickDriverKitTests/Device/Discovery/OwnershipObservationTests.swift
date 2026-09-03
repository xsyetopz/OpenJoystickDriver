import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct OwnershipObservationTests {
  @Test func inputMonitoringRequirementFollowsDiscoverySource() {
    #expect(DeviceManager.DiscoverySource.hid.requiresInputMonitoring)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .ioUSBHost).requiresInputMonitoring)
    #expect(!DeviceManager.DiscoverySource.rawUSB(route: .usbDriverKit).requiresInputMonitoring)
  }

  @Test(arguments: [
    (DeviceManager.DiscoverySource.hid, ControllerOwnershipObservation.nativeHIDVisible),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .ioUSBHost),
      ControllerOwnershipObservation.exclusiveRawUSB
    ),
    (
      DeviceManager.DiscoverySource.rawUSB(route: .usbDriverKit),
      ControllerOwnershipObservation.driverKitOwnedUSB
    )
  ]) func discoverySourceDerivesOwnership(
    source: DeviceManager.DiscoverySource,
    expected: ControllerOwnershipObservation
  ) {
    let info = DeviceManager.DeviceInfo(
      name: "Test controller",
      connection: "USB",
      serialNumber: nil,
      discoverySource: source
    )

    #expect(info.ownershipObservation == expected)
  }

  @Test func missingDeviceLookupIsUnknown() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let identifier = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)

    #expect(await manager.ownershipObservation(for: identifier) == .unknown)
  }

  @Test func deviceDescriptionRoundTripSurfacesOwnershipAndDuplicateRisk() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Test controller",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "Generic HID",
      connection: "HID",
      discoverySource: .hid,
      physicalOwnership: .nativeHIDVisible,
      duplicateExposureRisk: .nativeHIDVisible,
      serialNumber: nil
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )

    #expect(decoded.physicalOwnership == .nativeHIDVisible)
    #expect(decoded.duplicateExposureRisk == .nativeHIDVisible)
  }
}
