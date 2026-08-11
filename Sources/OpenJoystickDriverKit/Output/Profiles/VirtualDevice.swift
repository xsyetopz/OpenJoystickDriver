import Foundation
/// Stable identity shared by DriverKit relay configuration, discovery, and diagnostics.
package enum DriverKitRelayIdentity {
  package static let runtimeServiceClass = "SwifterKitRuntimeService"
  package static let bundleIdentifier = "com.openjoystickdriver.VirtualHIDDevice"
  package static let transport = "USB"
  package static let vendorID: UInt32 = 0x4F4A
  package static let productID: UInt32 = 0x4447
  package static let versionNumber: UInt32 = 0x0408
  package static let locationID: UInt32 = 0x4F4A_4401
  package static let manufacturer = "OpenJoystickDriver"
  package static let product = "OpenJoystickDriver DriverKit Relay"
  package static let serialNumber = "OpenJoystickDriver-DriverKit"
  package static let primaryUsagePage: UInt32 = 0xFF00
  package static let primaryUsage: UInt32 = 1
  package static let reportSize = 15

  package static let reportDescriptor: [UInt8] = [
    0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x0F,
    0x09, 0x02, 0x91, 0x02, 0x09, 0x03, 0x81, 0x02, 0xC0,
  ]

  package static func matches(
    runtimeClass: String?,
    transport: String?,
    vendorID: UInt32,
    productID: UInt32,
    versionNumber: UInt32,
    locationID: UInt32,
    manufacturer: String?,
    product: String?,
    serialNumber: String?,
    primaryUsagePage: UInt32,
    primaryUsage: UInt32
  ) -> Bool {
    runtimeClass == Self.runtimeServiceClass && transport == Self.transport
      && vendorID == Self.vendorID && productID == Self.productID
      && versionNumber == Self.versionNumber && locationID == Self.locationID
      && manufacturer == Self.manufacturer && product == Self.product
      && serialNumber == Self.serialNumber && primaryUsagePage == Self.primaryUsagePage
      && primaryUsage == Self.primaryUsage
  }
}

/// Constants used to identify and exclude OpenJoystickDriver-created virtual devices
/// from the input detection pipeline.
public enum UserSpaceVirtualDeviceConstants {
  /// Serial number prefix assigned to user-space virtual gamepads (IOHIDUserDevice).
  ///
  /// We create one IOHIDUserDevice per connected physical controller, so the
  /// serial number must be unique per virtual device. We keep a stable prefix
  /// so we can reliably filter our own devices from the input pipeline.
  public static let serialPrefix = "OpenJoystickDriver-UserSpace:"

  /// Product string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let product = "OpenJoystickDriver Virtual Gamepad"

  /// Manufacturer string used for the user-space virtual gamepad (IOHIDUserDevice).
  public static let manufacturer = "OpenJoystickDriver"

  /// Logical route token used by the bootstrap/shared Compatibility device.
  ///
  /// Dedicated per-consumer devices encode a different token in their serial
  /// number so the foreground monitor can distinguish them in IORegistry.
  public static let sharedRouteToken = "shared"

  /// Returns true when a SerialNumber belongs to an OpenJoystickDriver user-space device.
  public static func isOJDUserSpaceSerial(_ serial: String?) -> Bool {
    guard let serial else { return false }
    return serial.hasPrefix(serialPrefix)
  }

  /// Builds a stable, non-sensitive serial number for a virtual device.
  ///
  /// We hash the physical identifier so we don't leak hardware serial numbers.
  public static func serialNumber(for identifier: DeviceIdentifier, routeToken: String? = nil)
    -> String
  {
    let physicalHash = hex64(fnv1a64(stableKey(for: identifier)))
    let encodedRouteToken = routeToken ?? sharedRouteToken
    return serialPrefix + encodedRouteToken + ":" + physicalHash
  }

  /// Computes a stable LocationID in the OJD namespace for this physical identifier.
  public static func locationID(for identifier: DeviceIdentifier, routeToken: String? = nil)
    -> UInt32
  {
    let routeKey =
      (routeToken == nil || routeToken == sharedRouteToken) ? "" : "\(routeToken ?? ""):"
    let h = fnv1a64(routeKey + stableKey(for: identifier))
    let low16 = UInt32(truncatingIfNeeded: h & 0xFFFF)
    // Avoid 0/1 because some consumers treat these as special/invalid.
    let safeLow16 = (low16 <= 1) ? (low16 &+ 2) : low16
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | safeLow16
  }

  /// Returns the encoded route token carried by an OJD user-space serial.
  public static func routeToken(from serial: String?) -> String? {
    guard let serial, serial.hasPrefix(serialPrefix) else { return nil }
    let suffix = String(serial.dropFirst(serialPrefix.count))
    let parts = suffix.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, parts[1].count == 16,
      parts[1].allSatisfy(\.isHexDigit)
    else { return nil }
    return String(parts[0])
  }

  /// Returns the stable dedicated route token for one consumer bundle root.
  public static func dedicatedRouteToken(forConsumerBundleRootPath bundleRootPath: String) -> String
  { "consumer-" + hex64(fnv1a64(bundleRootPath)) }

  // MARK: - Private helpers

  private static func stableKey(for identifier: DeviceIdentifier) -> String {
    // Prefer physical serial when available, fall back to locationID.
    // IMPORTANT: this key is only used as hash input; it is not exposed to consumers.
    let sn = identifier.serialNumber ?? ""
    let loc = identifier.locationID.map { "\($0)" } ?? ""
    return "\(identifier.vendorID):\(identifier.productID):\(sn):\(loc)"
  }

  private static func fnv1a64(_ s: String) -> UInt64 {
    // FNV-1a 64-bit (deterministic, tiny, no extra deps).
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
      hash ^= UInt64(b)
      hash &*= 0x100_0000_01b3
    }
    return hash
  }

  private static func hex64(_ v: UInt64) -> String { String(format: "%016llx", v) }
}

/// Stable identity constants for OpenJoystickDriver-created virtual HID devices.
///
/// These values are used to:
/// - disambiguate our virtual devices from real controllers with the same VID/PID
/// - avoid ambiguous `LocationID=0/1` heuristics in some HID consumers
public enum VirtualDeviceIdentityConstants {
  /// User-space IOHIDUserDevice LocationID namespace.
  ///
  /// We intentionally use a *range* (not a single constant) so we can create one
  /// virtual controller per physical controller without collisions.
  ///
  /// The high 16 bits ("OJ") are a stable namespace. The low 16 bits are derived
  /// (deterministically) from the physical device identifier.
  public static let userSpaceLocationIDNamespace: UInt32 = 0x4F4A_0000  // "OJ" namespace
}
/// Defines the virtual HID device identity presented to the OS.
///
/// All input protocols normalize to XInputHID layout; the profile
/// only controls how the virtual device identifies itself to consumers.
public struct VirtualDeviceProfile: Equatable, Sendable {
  public let vendorID: Int
  public let productID: Int
  /// Value used for `kIOHIDVersionNumberKey` / SDL "product version".
  ///
  /// SDL includes this 16-bit value in the GUID it uses to look up controller mappings.
  /// For some SDL-based consumers on macOS, having the expected version is required for
  /// automatic mapping to be applied.
  public let versionNumber: Int
  public let productName: String
  public let manufacturer: String

  /// OpenJoystickDriver virtual gamepad. This standard HID GamePad identity avoids
  /// triggering device-specific HID parsers in consumers (e.g. SDL's Xbox path).
  public static let openJoystickDriver = Self(
    vendorID: 0x4F4A,  // "OJ"
    productID: 0x4447,  // "DG" (arbitrary, stable)
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  public static let openJoystickDriverSDL2_3 = Self(
    vendorID: 0x4F4A,
    productID: 0x4448,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  public static let openJoystickDriverGenericHID = Self(
    vendorID: 0x4F4A,
    productID: 0x4449,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Generic HID Gamepad",
    manufacturer: "OpenJoystickDriver"
  )

  /// Xbox One S is the standard XInput/GIP controller and the default
  /// normalization target for all protocols.
  public static let xboxOneS = Self(
    vendorID: 0x045E,
    productID: 0x02EA,
    // Important: SDL mapping DB entry for macOS expects version=0x0000 for GUID
    // `030000005e040000ea02000000000000` (Xbox One Controller, platform: Mac OS X).
    // Matching this makes SDL treat the device as a Gamepad with automatic mappings.
    versionNumber: 0x0000,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft"
  )

  /// Xbox 360 Controller (Wired), experimental on macOS.
  ///
  /// Many macOS stacks do not treat 045E:028E as a standard HID gamepad.
  public static let xbox360Wired = Self(
    vendorID: 0x045E,
    productID: 0x028E,
    versionNumber: 0x0000,
    productName: "Xbox 360 Wired Controller",
    manufacturer: "Microsoft"
  )

  /// SDL's macOS Xbox 360 HIDAPI-compatible shape.
  ///
  /// Stock SDL on macOS routes ordinary Xbox 360 identities away from HIDAPI,
  /// and hides the Steam virtual 045E:028E identity unless callers opt in. SDL
  /// explicitly accepts the ASTRO C40 Xbox 360 mode through HIDAPI, which gives
  /// some SDL consumers a no-launch-wrapper output-report rumble path.
  public static let sdlHIDAPIXbox360 = Self(
    vendorID: 0x9886,
    productID: 0x0024,
    versionNumber: 0x0000,
    productName: "ASTRO C40 TR Controller",
    manufacturer: "ASTRO Gaming"
  )

  /// SDL 2/3 compatibility identity.
  ///
  /// This profile is not exposed in the Compatibility UI. macOS GameController claims
  /// SDL-known third-party controller identities before SDL's IOKit backend can use them.
  /// Consumers use the generic OpenJoystickDriver user-space identity instead.
  public static let sdlGamepad = Self(
    vendorID: 0x1BAD,
    productID: 0xF901,
    versionNumber: 0x0000,
    productName: "Gamestop BB070 X360 Controller",
    manufacturer: "GameStop"
  )

  /// Default profile used when no protocol-specific profile is configured.
  /// Uses the OpenJoystickDriver virtual identity (generic HID GamePad).
  ///
  /// IMPORTANT: Do not default to spoofing a real controller's VID/PID unless
  /// the report descriptor and report bytes exactly match that controller's HID
  /// protocol. Many consumers (notably SDL) switch parsing logic based on VID/PID
  /// and will ignore inputs if the descriptor doesn't match their expectations.
  public static let `default` = openJoystickDriver
}
