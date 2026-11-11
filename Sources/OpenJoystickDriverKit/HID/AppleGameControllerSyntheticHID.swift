import Foundation

/// Identifies Apple GameController synthetic HID nodes without opening a user client.
///
/// GameController.framework publishes an `AppleGCSyntheticDevice` HID shim (product
/// `GamePad-1`, typically `045E:028E` / `_GCSyntheticDeviceType=Xbox360Controller`)
/// when it binds an Xbox pad. `IOHIDDeviceCreate` loads
/// `AppleSyntheticGameController.plugin` and `IOServiceOpen`s that node.
/// A wedged shim hangs stock SDL `hid_init` match-all and can hang OJD if discovery
/// opens it. Apple documents excluding these nodes from IOHID/IOService matching
/// with `"GCSyntheticDevice" = false` (`GCSyntheticDeviceKeys.h`).
///
/// This type holds the property names and the classification of their values. The macOS
/// platform target reads the IORegistry and builds the matching dictionaries.
public enum AppleGameControllerSyntheticHID: Sendable {
  /// `kIOHIDGCSyntheticDeviceKey` (`"GCSyntheticDevice"`).
  public static let propertyKey = "GCSyntheticDevice"
  /// The IOKit class of the synthetic node, `AppleGCSyntheticDevice`.
  public static let ioClassName = "AppleGCSyntheticDevice"
  /// The IORegistry property that names the synthetic device type, `_GCSyntheticDeviceType`.
  public static let deviceTypePropertyKey = "_GCSyntheticDeviceType"
  /// The device type of a synthetic Xbox 360 node, `Xbox360Controller`.
  public static let xbox360DeviceType = "Xbox360Controller"
  /// The text in the plug-in path that marks a synthetic node, `AppleSyntheticGameController`.
  public static let pluginPathToken = "AppleSyntheticGameController"

  /// Whether `value` is the boolean `true` of the `GCSyntheticDevice` property; false for nil and
  /// for any other type.
  public static func isSyntheticProperty(_ value: Any?) -> Bool {
    UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(value)
  }

  /// Whether `path` holds ``pluginPathToken``; false for nil.
  public static func isSyntheticPluginPath(_ path: String?) -> Bool {
    path?.contains(pluginPathToken) == true
  }

  /// Whether the node is synthetic, from its IORegistry properties; it never opens a user client.
  ///
  /// The node is synthetic when the `GCSyntheticDevice` property is true, the class name is
  /// ``ioClassName``, the node has a non-empty device type, or the plug-in path holds
  /// ``pluginPathToken``.
  /// Classifies a synthetic node from IORegistry properties. Does not open a user client.
  public static func isSyntheticDevice(
    className: String? = nil,
    syntheticProperty: Any? = nil,
    deviceType: String? = nil,
    pluginPath: String? = nil
  ) -> Bool {
    if isSyntheticProperty(syntheticProperty) { return true }
    if className == ioClassName { return true }
    if deviceType == xbox360DeviceType { return true }
    if let deviceType, !deviceType.isEmpty { return true }
    return isSyntheticPluginPath(pluginPath)
  }
}
