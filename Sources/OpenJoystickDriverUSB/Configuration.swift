import SwifterKit

/// Canonical configuration for OJD's restricted USBDriverKit extension.
///
/// The external bundle identifier is retained because Apple granted it for the
/// exclusive Microsoft GIP ownership case. It does not define the scope of the
/// generic `OpenJoystickDriverUSB` host facade.
public enum USBDriverKitExtensionConfiguration {
  public static let bundleIdentifier = "com.openjoystickdriver.XboxUSBDevice"
  public static let microsoftVendorID: UInt16 = 0x045E
  public static let microsoftProductIDs: [UInt16] = [
    0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12
  ]
  /// The sole source consumed by the host adapter and DriverKit generator.
  ///
  /// Interface matching belongs to the IOKit personality, while the USB transport
  /// entitlement stays limited to Apple's approved vendor/product pairs.
  public static let driver = DriverConfiguration(
    bundleIdentifier: bundleIdentifier,
    providerClass: "IOUSBHostInterface",
    matchingProperties: [
      "bConfigurationValue": .unsignedInteger(1), "bInterfaceNumber": .unsignedInteger(0),
      "bInterfaceClass": .unsignedInteger(0xFF), "bInterfaceSubClass": .unsignedInteger(0x47),
      "bInterfaceProtocol": .unsignedInteger(0xD0)
    ],
    capabilities: .usb,
    usbDevice: USBDeviceConfiguration(vendorID: microsoftVendorID, productIDs: microsoftProductIDs)
  )
}
