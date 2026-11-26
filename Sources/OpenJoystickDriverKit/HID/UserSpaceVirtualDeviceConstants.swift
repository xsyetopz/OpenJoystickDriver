import Foundation

/// Constants used to identify and exclude OpenJoystickDriver-created virtual devices
/// from the input detection pipeline.
public enum UserSpaceVirtualDeviceConstants {
  /// The kinds of event that a HID backend asks about.
  public enum PhysicalHIDEvent: Sendable {
    /// A physical device appeared.
    case deviceAdded
    /// A device sent an input report.
    case inputReport
    /// A device sent the value of an input element.
    case inputValue
    /// A device went away.
    case deviceRemoved
    /// The backend reads a device's report descriptor.
    case descriptorDiscovery
    /// The backend sends output to a device.
    case feedback
  }
  /// Serial number prefix assigned to user-space virtual gamepads (IOHIDUserDevice).
  ///
  /// We create one IOHIDUserDevice per connected physical controller, so the
  /// serial number must be unique per virtual device. We keep a stable prefix
  /// so we can reliably filter our own devices from the input pipeline.
  public static let serialPrefix = "OpenJoystickDriver-UserSpace:"

  /// Returns true when a SerialNumber belongs to an OpenJoystickDriver user-space device.
  public static func isOJDUserSpaceSerial(_ serial: String?) -> Bool {
    guard let serial else { return false }
    return serial.hasPrefix(serialPrefix)
  }

  /// Returns true when a HID location belongs to OJD's reserved user-space namespace.
  public static func isOJDUserSpaceLocationID(_ locationID: UInt32) -> Bool {
    (locationID & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace
  }

  /// Fail-closed admission check used by the IOKit physical HID input backend.
  ///
  /// Virtual HID profiles spoof third-party product names, transports, and
  /// VID/PID tuples. Apple does not guarantee that every property is surfaced on every callback,
  /// so no single marker is sufficient. Any OJD-owned marker, Apple's synthetic marker
  /// (`GCSyntheticDevice`), or a
  /// framework-reported virtual transport excludes the device from physical input discovery.
  public static func acceptsPhysicalHIDDevice(
    serialNumber: String?,
    productName: String?,
    transport: String?,
    locationID: UInt32,
    syntheticProperty: Any?
  ) -> Bool {
    if isOJDUserSpaceSerial(serialNumber) { return false }
    if productName == VirtualDeviceProfile.generic.productName { return false }
    if isOJDUserSpaceLocationID(locationID) { return false }
    if transport?.caseInsensitiveCompare("Virtual") == .orderedSame { return false }
    return !AppleGameControllerSyntheticHID.isSyntheticDevice(syntheticProperty: syntheticProperty)
  }

  /// Whether `value` is the boolean `true` of Apple's `GCSyntheticDevice` property; false for nil
  /// and for any other type.
  public static func isAppleGameControllerSyntheticDevice(_ value: Any?) -> Bool {
    guard let value else { return false }
    let cfValue = value as CFTypeRef
    guard CFGetTypeID(cfValue) == CFBooleanGetTypeID() else { return false }
    return unsafe CFBooleanGetValue(unsafeDowncast(cfValue, to: CFBoolean.self))
  }

  /// Whether the backend may process `event`; false for the events of Apple's synthetic device.
  ///
  /// The kind of event does not change the answer.
  public static func acceptsPhysicalHIDEvent(
    _ event: PhysicalHIDEvent,
    syntheticProperty: Any?
  ) -> Bool {
    _ = event
    return !isAppleGameControllerSyntheticDevice(syntheticProperty)
  }

  /// Builds a stable, non-sensitive serial number for a virtual device.
  ///
  /// We hash the physical identifier so we don't leak hardware serial numbers.
  public static func serialNumber(for identifier: LogicalControllerID) -> String {
    serialNumber(forKey: stableKey(for: identifier))
  }

  /// Computes a stable LocationID in the OJD namespace for this physical identifier.
  public static func locationID(for identifier: LogicalControllerID) -> UInt32 {
    locationID(forKey: stableKey(for: identifier))
  }

  /// The virtual serial number hashed from `key`.
  static func serialNumber(forKey key: String) -> String {
    serialPrefix + hex64(fnv1a64(key))
  }

  /// The virtual LocationID hashed from `key`.
  static func locationID(forKey key: String) -> UInt32 {
    let low16 = UInt32(truncatingIfNeeded: fnv1a64(key) & 0xFFFF)
    // Avoid 0/1 because some consumers treat these as special/invalid.
    let safeLow16 = (low16 <= 1) ? (low16 &+ 2) : low16
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | safeLow16
  }

  /// The LocationID after `locationID`, wrapping within the 16 low bits and skipping 0 and 1.
  static func nextLocationID(after locationID: UInt32) -> UInt32 {
    let next = (locationID &+ 1) & 0xFFFF
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | (next <= 1 ? 2 : next)
  }

  // MARK: - Identity keys

  /// The text that the hash of a virtual device's identity is taken from.
  ///
  /// It joins the vendor ID, the product ID, the serial number, the location ID (only without a
  /// serial number, or when `includingLocation`) and the interface number.
  static func stableKey(
    for identifier: LogicalControllerID,
    includingLocation: Bool = false
  ) -> String {
    // Prefer physical serial when available, fall back to locationID. A serial identifies the
    // controller across reconnects on another port, so the port must not change the virtual
    // identity. The interface keeps each logical controller of one physical device distinct.
    // IMPORTANT: this key is only used as hash input; it is not exposed to consumers.
    let identity = identifier.hardware
    let sn = identity.serialNumber ?? ""
    let location = (identifier.address?.locationID).map { "\($0)" } ?? ""
    let loc = (sn.isEmpty || includingLocation) ? location : ""
    let interface = identifier.address?.interfaceNumber.map { "\($0)" } ?? ""
    return "\(identity.model.vendorID):\(identity.model.productID):\(sn):\(loc):\(interface)"
  }

  /// The 64-bit FNV-1a hash of `s`.
  private static func fnv1a64(_ s: String) -> UInt64 {
    // FNV-1a 64-bit (deterministic, tiny, no extra deps).
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
      hash ^= UInt64(b)
      hash &*= 0x100_0000_01b3
    }
    return hash
  }

  /// `v` as 16 lower-case hex digits.
  private static func hex64(_ v: UInt64) -> String { unsafe String(format: "%016llx", v) }
}
