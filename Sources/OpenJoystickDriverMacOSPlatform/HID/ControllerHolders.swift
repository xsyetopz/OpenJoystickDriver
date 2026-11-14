import Foundation
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

/// Reads the processes that hold a controller open from the IORegistry user clients below it.
package enum ControllerHolders {
  /// The registry class of a controller's root and its vendor, product and location keys.
  ///
  /// The USB device comes first because its interfaces and its HID device sit below it; a
  /// Bluetooth controller has only the HID device.
  private static let roots:
    [(className: String, vendor: String, product: String, location: String)] =
      [
        ("IOUSBHostDevice", "idVendor", "idProduct", "locationID"),
        (kIOHIDDeviceKey, kIOHIDVendorIDKey, kIOHIDProductIDKey, kIOHIDLocationIDKey),
      ]

  /// Every process with a user client under the controller's USB device.
  ///
  /// The HID device stands in when no USB device matches. A nil `locationID` matches every
  /// location of the model.
  package static func holders(
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32?
  ) -> [USBExclusiveOwner] {
    for root in roots {
      let creators = creators(underEach: root.className) { properties in
        properties[root.vendor] as? Int == Int(vendorID)
          && properties[root.product] as? Int == Int(productID)
          && locationID.map { properties[root.location] as? Int == Int($0) } ?? true
      }
      if let creators { return holders(creators: creators) }
    }
    return []
  }

  /// The holders the `IOUserClientCreator` values name, one per process, in process ID order.
  static func holders(creators: [String]) -> [USBExclusiveOwner] {
    creators.compactMap(USBExclusiveOwner.init(registryValue:))
      .reduce(into: [USBExclusiveOwner]()) { if !$0.contains($1) { $0.append($1) } }
      .sorted { ($0.processID ?? -1, $0.name) < ($1.processID ?? -1, $1.name) }
  }

  /// The `IOUserClientCreator` values below each `className` service whose properties pass
  /// `matches`; nil when no service passes.
  private static func creators(
    underEach className: String,
    where matches: ([String: Any]) -> Bool
  ) -> [String]? {
    var iterator = io_iterator_t()
    guard
      unsafe IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching(className),
        &iterator
      )
        == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var result: [String]?
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      guard let properties = HIDInputReportDrops.registryProperties(service), matches(properties)
      else { continue }
      result = (result ?? []) + creators(under: service)
    }
    return result
  }

  /// The `IOUserClientCreator` values of every service-plane descendant of `root`.
  private static func creators(under root: io_registry_entry_t) -> [String] {
    var iterator = io_iterator_t()
    guard
      unsafe IORegistryEntryCreateIterator(
        root,
        kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively),
        &iterator
      ) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var result: [String] = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      let value = unsafe IORegistryEntryCreateCFProperty(
        entry,
        "IOUserClientCreator" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue()
      if let creator = value as? String { result.append(creator) }
    }
    return result
  }
}
