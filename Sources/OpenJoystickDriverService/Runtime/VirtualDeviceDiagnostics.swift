import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

/// Lists the HID gamepads on the system for the virtual device diagnostics.
enum VirtualDeviceDiagnostics {
  /// The registry key of the driver class of a device.
  private static let ioUserClassKey = "IOUserClass"

  /// Returns the HID gamepads on the system, the virtual ones of OJD first.
  static func enumerateHIDGamepads() -> [ApplicationServiceHIDGamepadSnapshot] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics as CFDictionary
    )
    // Matching lists the devices and their properties; opening them would only fail on devices
    // the service may not open.
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    return devices.compactMap(snapshot).sorted(by: snapshotOrder)
  }

  /// Describes `device` if it is an OJD virtual gamepad or looks like a gamepad; nil otherwise.
  private static func snapshot(_ device: IOHIDDevice) -> ApplicationServiceHIDGamepadSnapshot? {
    let location = intProp(device, kIOHIDLocationIDKey)
    let serial = strProp(device, kIOHIDSerialNumberKey)
    let isOJD =
      UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
      || ((UInt32(truncatingIfNeeded: location) & 0xFFFF_0000)
        == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace)
    guard isOJD || looksLikeGamepad(device) else { return nil }

    return ApplicationServiceHIDGamepadSnapshot(
      vendorID: UInt16(truncatingIfNeeded: intProp(device, kIOHIDVendorIDKey)),
      productID: UInt16(truncatingIfNeeded: intProp(device, kIOHIDProductIDKey)),
      product: strProp(device, kIOHIDProductKey),
      transport: strProp(device, kIOHIDTransportKey),
      locationID: location == 0 ? nil : UInt32(truncatingIfNeeded: location),
      serialKind: serialKind(serial),
      ioUserClass: IOHIDDeviceGetProperty(device, ioUserClassKey as CFString) as? String,
      isOJDUserSpace: isOJD,
      isGameControllerSupported: GCController.supportsHIDDevice(device)
    )
  }

  /// Game pads, joysticks, and multi-axis controllers, by primary usage or any usage pair.
  private static func looksLikeGamepad(_ device: IOHIDDevice) -> Bool {
    func isGameInput(page: Int, usage: Int) -> Bool {
      page == kHIDPage_GenericDesktop
        && [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController].contains(
          usage
        )
    }
    if isGameInput(
      page: intProp(device, kIOHIDPrimaryUsagePageKey),
      usage: intProp(device, kIOHIDPrimaryUsageKey)
    ) {
      return true
    }
    guard
      let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [[String: Any]]
    else { return false }
    return pairs.contains { pair in
      isGameInput(
        page: pair[kIOHIDDeviceUsagePageKey as String] as? Int ?? 0,
        usage: pair[kIOHIDDeviceUsageKey as String] as? Int ?? 0
      )
    }
  }

  /// Returns the integer property `key` of `device`, or 0 when it has none.
  private static func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  /// Returns the string property `key` of `device`, or nil when it has none.
  private static func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }
}

/// Classifies a serial number as absent, present, or one of the OJD user-space devices.
private func serialKind(_ serial: String?) -> ApplicationServiceSerialKind {
  guard let serial, !serial.isEmpty else { return .none }
  return UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) ? .ojdUserSpace : .present
}

/// Orders the OJD virtual devices first, then by vendor ID and product ID.
private func snapshotOrder(
  _ lhs: ApplicationServiceHIDGamepadSnapshot,
  _ rhs: ApplicationServiceHIDGamepadSnapshot
) -> Bool {
  if lhs.isOJDUserSpace != rhs.isOJDUserSpace { return lhs.isOJDUserSpace && !rhs.isOJDUserSpace }
  if lhs.vendorID != rhs.vendorID { return lhs.vendorID < rhs.vendorID }
  return lhs.productID < rhs.productID
}
