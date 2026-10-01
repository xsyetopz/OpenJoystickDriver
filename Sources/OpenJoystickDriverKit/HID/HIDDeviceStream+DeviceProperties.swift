import Foundation
import IOKit
import IOKit.hid

extension HIDDeviceStream {
  /// Reads an integer property from an IOKit HID device.
  ///
  /// Returns 0 if missing.
  func deviceProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  func physicalDeviceObservation(
    for device: IOHIDDevice,
    vendorID: UInt16,
    productID: UInt16,
    transportProperty: String?,
    nativePassThrough: Bool
  ) -> PhysicalDevice {
    let primaryUsage = HIDUsageSignature(
      usagePage: unsignedProperty(device, kIOHIDPrimaryUsagePageKey).flatMap(UInt32.init(exactly:)),
      usage: unsignedProperty(device, kIOHIDPrimaryUsageKey).flatMap(UInt32.init(exactly:))
    )
    let usagePairsValue = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
    let collectionUsages = (usagePairsValue as? [[String: Any]])?.map { pair in
      HIDUsageSignature(
        usagePage: (pair[kIOHIDDeviceUsagePageKey] as? Int).flatMap { UInt32(exactly: $0) },
        usage: (pair[kIOHIDDeviceUsageKey] as? Int).flatMap { UInt32(exactly: $0) }
      )
    }
    let elements =
      IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
      as? [IOHIDElement]
    let reportKinds: [(PhysicalHIDReportKind, String)] = [
      (.input, kIOHIDMaxInputReportSizeKey), (.output, kIOHIDMaxOutputReportSizeKey),
      (.feature, kIOHIDMaxFeatureReportSizeKey),
    ]
    let reports = elements.map { elements in
      reportKinds.map { kind, maximumSizeKey in
        let identifiers = elements.filter { Self.reportKind(for: $0) == kind }.map {
          IOHIDElementGetReportID($0)
        }.filter { $0 != 0 }
        return PhysicalHIDReportSignature(
          kind: kind,
          reportIDs: Array(Set(identifiers)).sorted(),
          maximumLengthBytes: unsignedProperty(device, maximumSizeKey).flatMap(
            UInt32.init(exactly:)
          )
        )
      }
    }
    let descriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data
    let hostTransport = Self.hostTransport(forTransportProperty: transportProperty)
    let usageFacts = [primaryUsage] + (collectionUsages ?? [])
    let hasControllerCollection: Bool?
    if usageFacts.contains(where: Self.isGamePadOrJoystick) {
      hasControllerCollection = true
    } else if let collectionUsages,
      collectionUsages.allSatisfy({ $0.usagePage != nil && $0.usage != nil })
    {
      hasControllerCollection = false
    } else {
      hasControllerCollection = nil
    }
    let hidLayout = HIDLayoutSummary(
      hasGamePadOrJoystickCollection: hasControllerCollection,
      hasUsableElements: elements.map { $0.contains { Self.reportKind(for: $0) == .input } },
      primaryUsage: primaryUsage.usagePage == nil && primaryUsage.usage == nil ? nil : primaryUsage,
      collectionUsages: collectionUsages,
      reportDescriptor: descriptor,
      reports: reports
    )
    return PhysicalDevice(
      platformUniqueIdentifier: IOHIDDeviceGetProperty(
        device,
        kIOHIDPhysicalDeviceUniqueIDKey as CFString
      ) as? String,
      vendorID: vendorID,
      productID: productID,
      deviceRelease: unsignedProperty(device, kIOHIDVersionNumberKey).flatMap(
        UInt16.init(exactly:)
      ),
      manufacturer: IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String,
      productName: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
      serialNumber: IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
      transportProperty: transportProperty,
      physicalLocationIdentifier: unsignedProperty(device, kIOHIDLocationIDKey).flatMap(
        UInt32.init(exactly:)
      ),
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: hostTransport == .usb ? Self.usbInterfaceNumber(for: device) : nil,
          hostTransport: hostTransport,
          accessBackend: .ioHID,
          hidLayout: hidLayout
        )
      ],
      nativePassThrough: nativePassThrough
    )
  }

  /// The `bInterfaceNumber` of the USB interface a HID device is published on, read from the
  /// nearest `IOUSBHostInterface` among its IORegistry service-plane parents. Nil when there is
  /// none. Callers read it only for USB-hosted devices, since a Bluetooth radio can itself sit on
  /// an internal USB interface.
  static func usbInterfaceNumber(for device: IOHIDDevice) -> UInt8? {
    var entry = IOHIDDeviceGetService(device)
    guard entry != 0, IOObjectRetain(entry) == KERN_SUCCESS else { return nil }
    while IOObjectConformsTo(entry, "IOUSBHostInterface") == 0 {
      var parent: io_registry_entry_t = 0
      let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
      IOObjectRelease(entry)
      guard result == KERN_SUCCESS else { return nil }
      entry = parent
    }
    defer { IOObjectRelease(entry) }
    let value = IORegistryEntryCreateCFProperty(
      entry,
      "bInterfaceNumber" as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue()
    return (value as? Int).flatMap(UInt8.init(exactly:))
  }

  /// Maps the IOHID `Transport` property to the host link; nil for unknown values.
  static func hostTransport(forTransportProperty property: String?) -> PhysicalTransport? {
    switch property {
    case kIOHIDTransportUSBValue: .usb
    case kIOHIDTransportBluetoothValue: .bluetoothClassic
    case kIOHIDTransportBluetoothLowEnergyValue: .bluetoothLE
    default: nil
    }
  }

  func unsignedProperty(_ device: IOHIDDevice, _ key: String) -> UInt64? {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) as? Int else { return nil }
    return UInt64(exactly: value)
  }

  private static func isGamePadOrJoystick(_ usage: HIDUsageSignature) -> Bool {
    guard usage.usagePage == UInt32(kHIDPage_GenericDesktop), let value = usage.usage else {
      return false
    }
    return value == UInt32(kHIDUsage_GD_GamePad) || value == UInt32(kHIDUsage_GD_Joystick)
  }

  private static func reportKind(for element: IOHIDElement) -> PhysicalHIDReportKind? {
    switch IOHIDElementGetType(element) {
    case kIOHIDElementTypeInput_Misc, kIOHIDElementTypeInput_Button, kIOHIDElementTypeInput_Axis,
      kIOHIDElementTypeInput_ScanCodes, kIOHIDElementTypeInput_NULL:
      .input
    case kIOHIDElementTypeOutput: .output
    case kIOHIDElementTypeFeature: .feature
    default: nil
    }
  }
}
