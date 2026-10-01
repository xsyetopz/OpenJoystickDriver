import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

enum VirtualDeviceDiagnostics {
  private static let ioUserClassKey = "IOUserClass"

  static func enumerateHIDGamepads() -> [ApplicationServiceHIDGamepadSnapshot] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(
      manager,
      AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics as CFDictionary
    )
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
      print("[VirtualDeviceDiagnostics] IOHIDManagerOpen warning: \(String(openResult, radix: 16))")
    }

    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    let snapshots = devices.compactMap(snapshot).sorted(by: snapshotOrder)
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    return snapshots
  }

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

  private static func intProp(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  private static func strProp(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }
}

private func serialKind(_ serial: String?) -> ApplicationServiceSerialKind {
  guard let serial, !serial.isEmpty else { return .none }
  return UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) ? .ojdUserSpace : .present
}

private func snapshotOrder(
  _ lhs: ApplicationServiceHIDGamepadSnapshot,
  _ rhs: ApplicationServiceHIDGamepadSnapshot
) -> Bool {
  if lhs.isOJDUserSpace != rhs.isOJDUserSpace { return lhs.isOJDUserSpace && !rhs.isOJDUserSpace }
  if lhs.vendorID != rhs.vendorID { return lhs.vendorID < rhs.vendorID }
  return lhs.productID < rhs.productID
}
