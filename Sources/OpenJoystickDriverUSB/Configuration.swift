public import OpenJoystickDriverKit
public import SwifterKit

/// Canonical configuration for OJD's restricted USBDriverKit extension.
///
/// The external bundle identifier is retained because Apple granted it for the
/// exclusive Microsoft GIP ownership case. It does not define the scope of the
/// generic `OpenJoystickDriverUSB` host facade.
public enum USBDriverKitExtensionConfiguration {
  /// The bundle identifier of the DriverKit transport extension.
  public static let extensionID = "com.openjoystickdriver.XboxUSBDevice"
  /// The Microsoft USB vendor ID.
  public static let microsoftVendorID: UInt16 = 0x045E
  /// The Microsoft product IDs in Apple's `transport.usb` grant; the extension matches no others.
  public static let microsoftProductIDs: [UInt16] = [
    0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12,
  ]

  /// The records' models that Apple's own `XboxGamepad` driver extension holds, sorted.
  ///
  /// Apple's driver holds the USB interface of these models, so the direct route cannot open them
  /// and only OJD's extension can take them over. The other models have no owner and use the
  /// direct route.
  public static func appleHeldModels(in records: ControllerRecordSet) -> [ControllerModelID] {
    records.records.values.filter(\.heldByAppleDriver).map(\.model).sorted()
  }

  /// The records' models whose route is `ExtensionOwned`, sorted.
  public static func extensionOwnedModels(in records: ControllerRecordSet) -> [ControllerModelID] {
    records.records.values.filter { $0.route == .extensionOwned }.map(\.model).sorted()
  }

  /// The match list: the product IDs of `models` that Apple's grant covers, sorted.
  public static func matchedProductIDs(
    extensionOwned models: some Sequence<ControllerModelID>
  ) -> [UInt16] {
    models.filter(isGranted).map(\.productID).sorted()
  }

  /// The `models` Apple's grant does not cover, sorted; the generator refuses to build with any.
  public static func modelsOutsideGrant(
    extensionOwned models: some Sequence<ControllerModelID>
  ) -> [ControllerModelID] {
    models.filter { !isGranted($0) }.sorted()
  }

  /// Tells whether the entitlement grant covers `model`.
  private static func isGranted(_ model: ControllerModelID) -> Bool {
    model.vendorID == microsoftVendorID && microsoftProductIDs.contains(model.productID)
  }

  /// The `XboxGIP` signature from the bundled protocol description, and its data interface.
  private static let (gipSignature, gipDataInterface) = {
    guard let signature = ProtocolInterfaceSignature.bundled(.xboxGIP, variant: .usb),
      let interface = signature.requiredInterfaceNumber
    else { fatalError("[USBDriverKit] The XboxGIP description has no data interface signature") }
    return (signature, interface)
  }()

  /// The sole source consumed by the host adapter and DriverKit generator.
  ///
  /// Interface matching belongs to the IOKit personality, while the USB transport
  /// entitlement stays limited to the bundled `ExtensionOwned` records within Apple's grant.
  public static let driver = DriverConfiguration(
    bundleIdentifier: extensionID,
    providerClass: "IOUSBHostInterface",
    matchingProperties: [
      "bConfigurationValue": .unsignedInteger(1),
      "bInterfaceNumber": .unsignedInteger(UInt64(gipDataInterface)),
      "bInterfaceClass": .unsignedInteger(UInt64(gipSignature.interfaceClass)),
      "bInterfaceSubClass": .unsignedInteger(UInt64(gipSignature.interfaceSubclass)),
      "bInterfaceProtocol": .unsignedInteger(UInt64(gipSignature.interfaceProtocol)),
    ],
    capabilities: .usb,
    usbDevice: USBDeviceConfiguration(
      vendorID: microsoftVendorID,
      productIDs: matchedProductIDs(
        extensionOwned: extensionOwnedModels(in: ControllerRecordSet.bundled)
      )
    )
  )
}
