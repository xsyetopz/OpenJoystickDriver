import SwifterKit

/// Configuration for OJD's only driver extension.
///
/// One extension carries two personalities that share SwifterKit's runtime: the virtual HID
/// device factory, matched on `IOUserResources`, and the USB personality that owns Microsoft GIP
/// interfaces. It lives in this module because only `OpenJoystickDriverUSB` and the generator
/// may depend on SwifterKit.
public enum VirtualHIDExtensionConfiguration {
  public static let bundleIdentifier = "com.openjoystickdriver.VirtualHIDDevice"
  public static let hidFactoryPersonality = "HIDFactory"
  public static let xboxUSBPersonality = "XboxUSB"
  /// One device per controller slot; the factory rejects creation beyond this limit.
  public static let maximumDevices = 8
  public static let microsoftVendorID: UInt16 = 0x045E
  /// The USB transport entitlement covers only these vendor/product pairs.
  public static let microsoftProductIDs: [UInt16] = [
    0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12,
  ]

  private static let personalities: [String: DriverConfiguration] = [
    hidFactoryPersonality: DriverConfiguration(
      bundleIdentifier: bundleIdentifier,
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .hid,
      hidDeviceFactory: HIDDeviceFactoryConfiguration(maximumDevices: maximumDevices)
    ),
    // Interface matching belongs to the IOKit personality, while the USB transport entitlement
    // stays limited to the approved vendor/product pairs.
    xboxUSBPersonality: DriverConfiguration(
      bundleIdentifier: bundleIdentifier,
      providerClass: "IOUSBHostInterface",
      matchingProperties: [
        "bConfigurationValue": .unsignedInteger(1), "bInterfaceNumber": .unsignedInteger(0),
        "bInterfaceClass": .unsignedInteger(0xFF), "bInterfaceSubClass": .unsignedInteger(0x47),
        "bInterfaceProtocol": .unsignedInteger(0xD0),
      ],
      capabilities: .usb,
      usbDevice: USBDeviceConfiguration(
        vendorID: microsoftVendorID,
        productIDs: microsoftProductIDs
      )
    ),
  ]

  /// The extension the generator builds. Without the USB personality it needs no USB transport
  /// entitlement, for signing profiles that lack one.
  public static func driverExtension(includingUSB: Bool = true) -> DriverExtensionConfiguration {
    DriverExtensionConfiguration(
      bundleIdentifier: bundleIdentifier,
      personalities: personalities.filter { includingUSB || $0.key != xboxUSBPersonality }
    )
  }

  /// The factory personality; its `serviceMatch` finds only the factory service.
  public static let hidFactory = personality(hidFactoryPersonality)
  /// The USB personality; its `serviceMatch` finds only services that own a GIP interface.
  public static let xboxUSB = personality(xboxUSBPersonality)

  private static func personality(_ name: String) -> DriverConfiguration {
    guard let personality = driverExtension().personality(name) else {
      preconditionFailure("Missing driver extension personality \(name)")
    }
    return personality
  }
}
