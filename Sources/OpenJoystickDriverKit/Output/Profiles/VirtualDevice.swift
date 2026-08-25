import Foundation

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

  /// Returns true when a SerialNumber belongs to an OpenJoystickDriver user-space device.
  public static func isOJDUserSpaceSerial(_ serial: String?) -> Bool {
    guard let serial else { return false }
    return serial.hasPrefix(serialPrefix)
  }

  /// Builds a stable, non-sensitive serial number for a virtual device.
  ///
  /// We hash the physical identifier so we don't leak hardware serial numbers.
  public static func serialNumber(for identifier: DeviceIdentifier) -> String {
    let physicalHash = hex64(fnv1a64(stableKey(for: identifier)))
    return serialPrefix + physicalHash
  }

  /// Computes a stable LocationID in the OJD namespace for this physical identifier.
  public static func locationID(for identifier: DeviceIdentifier) -> UInt32 {
    let h = fnv1a64(stableKey(for: identifier))
    let low16 = UInt32(truncatingIfNeeded: h & 0xFFFF)
    // Avoid 0/1 because some consumers treat these as special/invalid.
    let safeLow16 = (low16 <= 1) ? (low16 &+ 2) : low16
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | safeLow16
  }

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

  /// Default profile used when no protocol-specific profile is configured.
  /// Uses the OpenJoystickDriver virtual identity (generic HID GamePad).
  ///
  /// IMPORTANT: Do not default to spoofing a real controller's VID/PID unless
  /// the report descriptor and report bytes exactly match that controller's HID
  /// protocol. Many consumers (notably SDL) switch parsing logic based on VID/PID
  /// and will ignore inputs if the descriptor doesn't match their expectations.
  public static let `default` = openJoystickDriver
}
