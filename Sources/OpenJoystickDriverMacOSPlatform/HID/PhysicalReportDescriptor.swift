import Foundation
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

/// Reads HID report descriptors from the controllers macOS currently sees.
package enum PhysicalReportDescriptor {
  /// Copies the HID report descriptor from a currently connected physical HID device,
  /// preferring a wired USB device over any other transport.
  ///
  /// Skips virtual devices that OJD creates.
  package static func copy(
    vendorID: Int,
    productID: Int
  ) -> [UInt8]? {
    preferredDevice(vendorID: vendorID, productID: productID).map { [UInt8]($0.descriptor) }
  }

  /// Reads the identity and HID elements of the device that ``copy(vendorID:productID:)`` reads
  /// the descriptor of; nil when no such device is connected.
  package static func physicalDevice(vendorID: Int, productID: Int) -> PhysicalDevice? {
    guard let (device, _) = preferredDevice(vendorID: vendorID, productID: productID),
      let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID)
    else { return nil }
    return HIDDeviceStream().physicalDeviceObservation(
      for: device,
      vendorID: vendor,
      productID: product,
      transportProperty: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String,
      nativePassThrough: false,
      systemListsGameController: false,
      gameControllerSupported: false
    )
  }

  /// The preferred connected device of the model and its report descriptor.
  private static func preferredDevice(
    vendorID: Int,
    productID: Int
  ) -> (IOHIDDevice, descriptor: Data)? {
    let matching = AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics([
      kIOHIDVendorIDKey as String: vendorID, kIOHIDProductIDKey as String: productID,
    ])
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
    _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }

    let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []

    func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
      IOHIDDeviceGetProperty(dev, key as CFString) as? String
    }

    func score(_ dev: IOHIDDevice) -> Int {
      let transport = strProp(dev, kIOHIDTransportKey as String)
      let serial = strProp(dev, kIOHIDSerialNumberKey as String) ?? strProp(dev, "SerialNumber")
      if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || !PhysicalHIDBackendEventAdapter().acceptsDescriptor(
          syntheticProperty: IOHIDDeviceGetProperty(
            dev,
            AppleGameControllerSyntheticHID.propertyKey as CFString
          )
        )
      {
        return Int.min / 2
      }

      var s = 0
      if let transport, transport != "Virtual" { s += 1_000 }
      if transport == "USB" { s += 100 }
      return s
    }

    let candidates = devices.map { ($0, score($0)) }.sorted { a, b in a.1 > b.1 }

    for (dev, s) in candidates {
      if s <= Int.min / 4 { continue }
      if let data = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data {
        return (dev, data)
      }
    }
    return nil
  }
}
