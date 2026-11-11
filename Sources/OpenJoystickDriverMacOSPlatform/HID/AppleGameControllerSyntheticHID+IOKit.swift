import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

extension AppleGameControllerSyntheticHID {
  /// IOHIDManager / IOService matching fragment that excludes synthetics before create/open.
  package static var ioHIDMatchingExclusion: [String: Any] { [propertyKey: kCFBooleanFalse as Any] }

  /// Replacement for `IOHIDManagerSetDeviceMatching(nil)` that still skips Apple synthetics.
  package static var allHIDDevicesExcludingSynthetics: [String: Any] {
    ioHIDMatchingExcludingSynthetics([kIOProviderClassKey as String: kIOHIDDeviceKey as String])
  }

  /// Adds Apple's documented synthetic exclusion to an existing HID matching dictionary.
  package static func ioHIDMatchingExcludingSynthetics(_ matching: [String: Any]) -> [String: Any] {
    matching.merging(ioHIDMatchingExclusion) { _, new in new }
  }

  /// Reads IORegistry properties on `service`.
  ///
  /// Does not `IOServiceOpen`.
  package static func isSynthetic(service: io_service_t) -> Bool {
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
      syntheticProperty: cfProperty(service, propertyKey),
      deviceType: stringProperty(service, deviceTypePropertyKey),
      pluginPath: pluginPaths(service).first { isSyntheticPluginPath($0) }
    )
  }

  /// Tells whether `device` is a synthetic HID device that Apple's GameController framework
  /// creates.
  package static func isSynthetic(device: IOHIDDevice) -> Bool {
    let service = IOHIDDeviceGetService(device)
    if service != 0, isSynthetic(service: service) { return true }
    return isSyntheticDevice(
      syntheticProperty: IOHIDDeviceGetProperty(device, propertyKey as CFString)
    )
  }

  /// Reads the IORegistry property `key` of `service`.
  private static func cfProperty(_ service: io_service_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  /// Reads the string IORegistry property `key` of `service`.
  private static func stringProperty(_ service: io_service_t, _ key: String) -> String? {
    cfProperty(service, key) as? String
  }

  /// Returns the plug-in paths that `service` lists in `IOCFPlugInTypes`.
  private static func pluginPaths(_ service: io_service_t) -> [String] {
    guard let types = cfProperty(service, "IOCFPlugInTypes") as? [String: String] else { return [] }
    return Array(types.values)
  }
}
