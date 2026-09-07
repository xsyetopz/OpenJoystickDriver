import CoreHID
import Foundation
import IOKit
import IOKit.hid

/// Identifies Apple GameController synthetic HID nodes without opening a user client.
///
/// GameController.framework publishes an `AppleGCSyntheticDevice` HID shim (product
/// `GamePad-1`, typically `045E:028E` / `_GCSyntheticDeviceType=Xbox360Controller`)
/// when it binds an Xbox pad. `IOHIDDeviceCreate` / CoreHID `HIDDeviceClient`
/// load `AppleSyntheticGameController.plugin` and `IOServiceOpen` that node.
/// A wedged shim hangs stock SDL `hid_init` match-all and can hang OJD if discovery
/// opens it. Apple documents excluding these nodes from IOHID/IOService matching
/// with `"GCSyntheticDevice" = false` (`GCSyntheticDeviceKeys.h`).
public enum AppleGameControllerSyntheticHID: Sendable {
  /// `kIOHIDGCSyntheticDeviceKey` (`"GCSyntheticDevice"`).
  public static let propertyKey = "GCSyntheticDevice"
  public static let ioClassName = "AppleGCSyntheticDevice"
  public static let deviceTypePropertyKey = "_GCSyntheticDeviceType"
  public static let xbox360DeviceType = "Xbox360Controller"
  public static let productName = "GamePad-1"
  public static let pluginPathToken = "AppleSyntheticGameController"

  /// IOHIDManager / IOService matching fragment that excludes synthetics before create/open.
  public static var ioHIDMatchingExclusion: [String: Any] {
    [propertyKey: kCFBooleanFalse as Any]
  }

  /// CoreHID `DeviceMatchingCriteria.extraProperties` equivalent of ``ioHIDMatchingExclusion``.
  public static var ioHIDMatchingExclusionObjects: [String: any AnyObject] {
    [propertyKey: kCFBooleanFalse]
  }

  /// Replacement for `IOHIDManagerSetDeviceMatching(nil)` that still skips Apple synthetics.
  public static var allHIDDevicesExcludingSynthetics: [String: Any] {
    ioHIDMatchingExcludingSynthetics([
      kIOProviderClassKey as String: kIOHIDDeviceKey as String
    ])
  }

  /// Adds Apple's documented synthetic exclusion to an existing HID matching dictionary.
  public static func ioHIDMatchingExcludingSynthetics(_ matching: [String: Any]) -> [String: Any] {
    matching.merging(ioHIDMatchingExclusion) { _, new in new }
  }

  @available(macOS 15, *)
  public static func coreHIDMatchingCriteria(
    primaryUsage: HIDUsage? = nil,
    vendorID: UInt32? = nil,
    productID: UInt32? = nil
  ) -> HIDDeviceManager.DeviceMatchingCriteria {
    HIDDeviceManager.DeviceMatchingCriteria(
      primaryUsage: primaryUsage,
      vendorID: vendorID,
      productID: productID,
      extraProperties: ioHIDMatchingExclusionObjects
    )
  }

  public static func isSyntheticProperty(_ value: Any?) -> Bool {
    UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(value)
  }

  public static func isSyntheticPluginPath(_ path: String?) -> Bool {
    path?.contains(pluginPathToken) == true
  }

  /// Classifies a synthetic node from IORegistry properties. Does not open a user client.
  public static func isSyntheticDevice(
    className: String? = nil,
    productName: String? = nil,
    syntheticProperty: Any? = nil,
    deviceType: String? = nil,
    pluginPath: String? = nil
  ) -> Bool {
    if isSyntheticProperty(syntheticProperty) { return true }
    if className == ioClassName { return true }
    if productName == self.productName { return true }
    if deviceType == xbox360DeviceType { return true }
    if let deviceType, !deviceType.isEmpty { return true }
    return isSyntheticPluginPath(pluginPath)
  }

  /// Reads IORegistry properties on `service`. Does not `IOServiceOpen`.
  public static func isSynthetic(service: io_service_t) -> Bool {
    guard service != 0 else { return false }
    var className = [CChar](repeating: 0, count: 128)
    let resolvedClass: String?
    if IOObjectGetClass(service, &className) == kIOReturnSuccess {
      let bytes = className.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
      resolvedClass = String(bytes: bytes, encoding: .utf8)
    } else {
      resolvedClass = stringProperty(service, "IOClass")
    }
    return isSyntheticDevice(
      className: resolvedClass,
      productName: stringProperty(service, kIOHIDProductKey as String),
      syntheticProperty: cfProperty(service, propertyKey),
      deviceType: stringProperty(service, deviceTypePropertyKey),
      pluginPath: pluginPaths(service).first { isSyntheticPluginPath($0) }
    )
  }

  /// Looks up a registry entry ID and classifies it. Does not `IOServiceOpen`.
  public static func isSyntheticRegistryEntry(id: UInt64) -> Bool {
    guard id != 0 else { return false }
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, IORegistryEntryIDMatching(id))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }
    return isSynthetic(service: service)
  }

  public static func isSynthetic(device: IOHIDDevice) -> Bool {
    let service = IOHIDDeviceGetService(device)
    if service != 0, isSynthetic(service: service) { return true }
    return isSyntheticDevice(
      productName: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
      syntheticProperty: IOHIDDeviceGetProperty(device, propertyKey as CFString)
    )
  }

  private static func cfProperty(_ service: io_service_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(
      service,
      key as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue()
  }

  private static func stringProperty(_ service: io_service_t, _ key: String) -> String? {
    cfProperty(service, key) as? String
  }

  private static func pluginPaths(_ service: io_service_t) -> [String] {
    guard let types = cfProperty(service, "IOCFPlugInTypes") as? [String: String] else {
      return []
    }
    return Array(types.values)
  }
}
