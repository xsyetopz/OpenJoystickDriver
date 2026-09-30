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
/// Physical input is normalized to the internal virtual-gamepad state; the
/// profile controls the selected HID descriptor and consumer identity.
public struct VirtualDeviceProfile: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// Value used for `kIOHIDVersionNumberKey` / SDL "product version".
  ///
  /// SDL includes this 16-bit value in the GUID it uses to look up controller mappings.
  /// For some SDL-based consumers on macOS, having the expected version is required for
  /// automatic mapping to be applied.
  public let versionNumber: Int
  public let productName: String
  public let manufacturer: String
  public let transport: String

  /// Stable non-spoof Generic HID identity. Its name, version, descriptor, and report
  /// layout form one consumer contract; incompatible layouts require a new product ID.
  public static let openJoystickDriverGenericHID = Self(
    vendorID: 0x1209,
    productID: 0x4A4F,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Generic HID Gamepad",
    manufacturer: "OpenJoystickDriver",
    transport: "USB"
  )

  /// Xbox One S Bluetooth identity published by the `hid-xbox-one-s-bt` virtual profile.
  /// This is not XInputHID, XUSB, or GIP emulation.
  public static let xboxOneS = Self(
    vendorID: 0x045E,
    productID: 0x02FD,
    // Version 0x0000 matches SDL GUID `030000005e040000fd02000000000000`. On macOS SDL's HIDAPI
    // Xbox One driver owns this ID and decodes report bytes itself; the mapping DB is not used.
    versionNumber: 0x0000,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft",
    transport: "Bluetooth"
  )
}
