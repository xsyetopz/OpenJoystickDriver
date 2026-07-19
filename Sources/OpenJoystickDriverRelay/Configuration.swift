import OpenJoystickDriverKit
import SwifterKit

/// Authoritative configuration for OpenJoystickDriver's generated DriverKit relay.
public enum OpenJoystickDriverRelayConfiguration {
  /// The sole source consumed by both the runtime host and extension generator.
  public static let driver = DriverConfiguration(
    bundleIdentifier: DriverKitRelayIdentity.bundleIdentifier,
    providerClass: "IOUserResources",
    matchingProperties: ["IOResourceMatch": .string("IOKit")],
    capabilities: .hid,
    hidDevice: HIDDeviceConfiguration(
      reportDescriptor: DriverKitRelayIdentity.reportDescriptor,
      transport: DriverKitRelayIdentity.transport,
      vendorID: DriverKitRelayIdentity.vendorID,
      productID: DriverKitRelayIdentity.productID,
      versionNumber: DriverKitRelayIdentity.versionNumber,
      locationID: DriverKitRelayIdentity.locationID,
      manufacturer: DriverKitRelayIdentity.manufacturer,
      product: DriverKitRelayIdentity.product,
      serialNumber: DriverKitRelayIdentity.serialNumber,
      primaryUsagePage: DriverKitRelayIdentity.primaryUsagePage,
      primaryUsage: DriverKitRelayIdentity.primaryUsage,
      acceptedHostReportTypes: .output
    )
  )
}
