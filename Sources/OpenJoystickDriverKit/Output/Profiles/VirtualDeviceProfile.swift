/// Stable identity constants of the virtual HID devices that OJD creates.
///
/// They tell OJD's devices from real controllers with the same VID/PID, and they avoid the
/// `LocationID=0/1` guess of some HID consumers.
public enum VirtualDeviceIdentityConstants {
  /// The `IOHIDUserDevice` LocationID namespace of the user-space devices.
  ///
  /// A range, not a single value, so each physical controller can have its own virtual controller.
  /// The high 16 bits ("OJ") are a stable namespace. The low 16 bits derive from the physical
  /// device identifier.
  public static let userSpaceLocationIDNamespace: UInt32 = 0x4F4A_0000  // "OJ" namespace
}
/// Defines the virtual HID device identity presented to the OS.
///
/// Physical input is normalized to the internal virtual-gamepad state; the
/// profile controls the selected HID descriptor and consumer identity.
public struct VirtualDeviceProfile: Equatable, Sendable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// Value used for `kIOHIDVersionNumberKey` / SDL "product version".
  ///
  /// SDL includes this 16-bit value in the GUID it uses to look up controller mappings.
  /// For some SDL-based consumers on macOS, having the expected version is required for
  /// automatic mapping to be applied.
  public let versionNumber: Int
  /// The product name.
  public let productName: String
  /// The manufacturer name.
  public let manufacturer: String
  /// The transport the device reports.
  public let transport: String
  /// The control glyphs and system symbol the published product shows.
  public let glyphFamily: VirtualIdentityGlyphFamily

  /// The `Generic` persona's identity: a stable non-spoof Generic HID identity.
  ///
  /// Its name, version, descriptor, and report layout form one consumer contract; incompatible
  /// layouts require a new product ID. The values come from the bundled `VirtualDevice` record.
  public static var generic: Self { VirtualHIDProfileID.generic.identity }

  /// The `SDLCompatible` persona's identity, the Xbox Adaptive Controller over Bluetooth, whose
  /// reports are Xbox One GIP packets.
  ///
  /// SDL reads that ID with its Xbox One driver, and Apple's GameController framework does not
  /// bind it on a virtual device. This is not XInputHID or XUSB emulation. The values come from the
  /// bundled `VirtualDevice` record.
  public static var sdlCompatible: Self { VirtualHIDProfileID.sdlCompatible.identity }

  /// This profile with the identity of a persona over it.
  ///
  /// The transport and, unless the persona sets one, the version number stay those of the
  /// built-in profile, so the report descriptor and the report layout keep their contract.
  public func applying(_ identity: VirtualPersona.Identity) -> Self {
    Self(
      vendorID: identity.vendorID,
      productID: identity.productID,
      versionNumber: identity.versionNumber ?? versionNumber,
      productName: identity.productName,
      manufacturer: identity.manufacturer,
      transport: transport,
      glyphFamily: identity.glyphFamily
    )
  }
}
