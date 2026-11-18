import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

/// The element list the platform layer supplies to SDL's element order.
///
/// IOKit builds an `IOHIDElement` only from a device, so these read the devices the host has.
struct HIDElementDescriptionTests {
  private static func hostElements() -> [[IOHIDElement]] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    return devices.compactMap {
      IOHIDDeviceCopyMatchingElements($0, nil, IOOptionBits(kIOHIDOptionsTypeNone))
        as? [IOHIDElement]
    }
  }

  @Test
  func inputsAreInputElementsNumberedInListingOrder() {
    for elements in Self.hostElements() {
      let inputs = elements.filter { HIDDeviceStream.reportKind(for: $0) == .input }
      let listing = HIDElementDescription.inputs(of: elements)
      #expect(listing.map(\.arrivalOrder) == Array(inputs.indices))
      #expect(listing.map(\.cookie) == inputs.map { IOHIDElementGetCookie($0) })
      #expect(listing.map(\.usage) == inputs.map { IOHIDElementGetUsage($0) })
      #expect(listing.map(\.usagePage) == inputs.map { IOHIDElementGetUsagePage($0) })
      #expect(listing.map(\.logicalMinimum) == inputs.map { IOHIDElementGetLogicalMin($0) })
      #expect(listing.map(\.logicalMaximum) == inputs.map { IOHIDElementGetLogicalMax($0) })
    }
  }

  @Test
  func noElementsGiveNoList() {
    #expect(HIDElementDescription.inputs(of: []).isEmpty)
  }
}
