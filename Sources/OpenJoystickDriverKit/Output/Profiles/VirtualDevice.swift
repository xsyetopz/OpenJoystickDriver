import Foundation

/// Constants used to identify and exclude OpenJoystickDriver-created virtual devices
/// from the input detection pipeline.
public enum UserSpaceVirtualDeviceConstants {
  public enum PhysicalHIDEvent: Sendable {
    case deviceAdded
    case inputReport
    case inputValue
    case deviceRemoved
    case descriptorDiscovery
    case feedback
  }
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

  /// Returns true when a HID location belongs to OJD's reserved user-space namespace.
  public static func isOJDUserSpaceLocationID(_ locationID: UInt32) -> Bool {
    (locationID & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace
  }

  /// Fail-closed admission check shared by the IOKit and CoreHID input backends.
  ///
  /// Compatibility devices intentionally spoof third-party product names, transports, and
  /// VID/PID tuples. Apple does not guarantee that every property is surfaced on every callback,
  /// so no single marker is sufficient. Any OJD-owned marker, Apple's synthetic marker, or a
  /// framework-reported virtual transport excludes the device from physical input discovery.
  public static func acceptsPhysicalHIDDevice(
    serialNumber: String?,
    productName: String?,
    transport: String?,
    locationID: UInt32,
    syntheticProperty: Any?
  ) -> Bool {
    if isOJDUserSpaceSerial(serialNumber) { return false }
    if productName == product { return false }
    if isOJDUserSpaceLocationID(locationID) { return false }
    if transport?.caseInsensitiveCompare("Virtual") == .orderedSame { return false }
    return !isAppleGameControllerSyntheticDevice(syntheticProperty)
  }

  public static func isAppleGameControllerSyntheticDevice(_ value: Any?) -> Bool {
    guard let value else { return false }
    let cfValue = value as CFTypeRef
    guard CFGetTypeID(cfValue) == CFBooleanGetTypeID() else { return false }
    return CFBooleanGetValue(unsafeDowncast(cfValue, to: CFBoolean.self))
  }

  public static func acceptsPhysicalHIDEvent(_ event: PhysicalHIDEvent, syntheticProperty: Any?)
    -> Bool
  {
    _ = event
    return !isAppleGameControllerSyntheticDevice(syntheticProperty)
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

/// Minimal state machine shared by HID backend adapters for physical-device ownership.
public enum PhysicalHIDBackendEventPolicy {
  public static func acceptsDevice(
    serialNumber: String?,
    productName: String?,
    transport: String?,
    locationID: UInt32,
    syntheticProperty: Any?
  ) -> Bool {
    UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDDevice(
      serialNumber: serialNumber,
      productName: productName,
      transport: transport,
      locationID: locationID,
      syntheticProperty: syntheticProperty
    )
  }

  public static func accepts(
    _ event: UserSpaceVirtualDeviceConstants.PhysicalHIDEvent,
    syntheticProperty: Any?
  ) -> Bool {
    UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent(
      event,
      syntheticProperty: syntheticProperty
    )
  }
}

public struct PhysicalHIDTrackingStateMachine {
  private var locationsByDeviceID: [UInt64: UInt32] = [:]
  private var deviceIDsByLocation: [UInt32: Set<UInt64>] = [:]

  public init() {}

  @discardableResult public mutating func register(
    deviceID: UInt64,
    locationID: UInt32,
    syntheticProperty: Any?
  ) -> Bool {
    guard PhysicalHIDBackendEventPolicy.accepts(.deviceAdded, syntheticProperty: syntheticProperty),
      locationsByDeviceID[deviceID] == nil
    else { return false }
    locationsByDeviceID[deviceID] = locationID
    deviceIDsByLocation[locationID, default: []].insert(deviceID)
    return true
  }

  public func acceptsInput(deviceID: UInt64) -> Bool { locationsByDeviceID[deviceID] != nil }

  public func isTracked(deviceID: UInt64) -> Bool { locationsByDeviceID[deviceID] != nil }

  public func acceptsInput(locationID: UInt32) -> Bool {
    !(deviceIDsByLocation[locationID] ?? []).isEmpty
  }

  public func acceptsFeedback(locationID: UInt32) -> Bool { acceptsInput(locationID: locationID) }

  /// Removes one device and returns true only when its location is now fully disconnected.
  @discardableResult public mutating func remove(deviceID: UInt64) -> Bool {
    guard let locationID = locationsByDeviceID.removeValue(forKey: deviceID) else { return false }
    deviceIDsByLocation[locationID]?.remove(deviceID)
    guard deviceIDsByLocation[locationID]?.isEmpty == true else { return false }
    deviceIDsByLocation.removeValue(forKey: locationID)
    return true
  }

  /// Removes all devices at a location and returns whether a tracked location existed.
  @discardableResult public mutating func remove(locationID: UInt32) -> Bool {
    guard let deviceIDs = deviceIDsByLocation.removeValue(forKey: locationID), !deviceIDs.isEmpty
    else { return false }
    deviceIDs.forEach { locationsByDeviceID.removeValue(forKey: $0) }
    return true
  }
}

/// Backend-facing event adapter. HID framework callbacks delegate ownership,
/// forwarding, removal, feedback, and descriptor decisions here so adapters
/// cannot drift in their handling of physical versus synthetic devices.
public struct PhysicalHIDBackendEventAdapter {
  public struct RemovalDecision: Equatable, Sendable {
    public let wasTracked: Bool
    public let locationRemoved: Bool
    public let shouldCancelNotification: Bool
    public let shouldEmitDisconnect: Bool

    public init(
      wasTracked: Bool,
      locationRemoved: Bool,
      shouldCancelNotification: Bool,
      shouldEmitDisconnect: Bool
    ) {
      self.wasTracked = wasTracked
      self.locationRemoved = locationRemoved
      self.shouldCancelNotification = shouldCancelNotification
      self.shouldEmitDisconnect = shouldEmitDisconnect
    }
  }

  private var tracking = PhysicalHIDTrackingStateMachine()

  public init() {}

  @discardableResult public mutating func add(
    deviceID: UInt64,
    locationID: UInt32,
    syntheticProperty: Any?
  ) -> Bool {
    tracking.register(
      deviceID: deviceID,
      locationID: locationID,
      syntheticProperty: syntheticProperty
    )
  }

  public func acceptsInput(deviceID: UInt64) -> Bool { tracking.acceptsInput(deviceID: deviceID) }

  public func acceptsFeedback(locationID: UInt32) -> Bool {
    tracking.acceptsFeedback(locationID: locationID)
  }

  public func acceptsDescriptor(syntheticProperty: Any?) -> Bool {
    PhysicalHIDBackendEventPolicy.accepts(
      .descriptorDiscovery,
      syntheticProperty: syntheticProperty
    )
  }

  public mutating func remove(deviceID: UInt64) -> RemovalDecision {
    let wasTracked = tracking.isTracked(deviceID: deviceID)
    guard wasTracked else {
      return RemovalDecision(
        wasTracked: false,
        locationRemoved: false,
        shouldCancelNotification: false,
        shouldEmitDisconnect: false
      )
    }
    let locationRemoved = tracking.remove(deviceID: deviceID)
    return RemovalDecision(
      wasTracked: true,
      locationRemoved: locationRemoved,
      shouldCancelNotification: true,
      shouldEmitDisconnect: locationRemoved
    )
  }

  public func isTracked(deviceID: UInt64) -> Bool { tracking.isTracked(deviceID: deviceID) }
}

/// Thread-safe holder for backend callbacks and feedback callers that may run
/// on different queues. The holder lock is never held while a backend lock is
/// acquired, so callers can safely compose it with framework/device locks.
public final class SynchronizedPhysicalHIDBackendEventAdapter: @unchecked Sendable {
  private let lock = NSLock()
  private var adapter = PhysicalHIDBackendEventAdapter()

  public init() {}

  @discardableResult public func add(deviceID: UInt64, locationID: UInt32, syntheticProperty: Any?)
    -> Bool
  {
    lock.withLock {
      adapter.add(deviceID: deviceID, locationID: locationID, syntheticProperty: syntheticProperty)
    }
  }

  public func acceptsInput(deviceID: UInt64) -> Bool {
    lock.withLock { adapter.acceptsInput(deviceID: deviceID) }
  }

  public func acceptsFeedback(locationID: UInt32) -> Bool {
    lock.withLock { adapter.acceptsFeedback(locationID: locationID) }
  }

  public func acceptsDescriptor(syntheticProperty: Any?) -> Bool {
    lock.withLock { adapter.acceptsDescriptor(syntheticProperty: syntheticProperty) }
  }

  public func remove(deviceID: UInt64) -> PhysicalHIDBackendEventAdapter.RemovalDecision {
    lock.withLock { adapter.remove(deviceID: deviceID) }
  }

  public func isTracked(deviceID: UInt64) -> Bool {
    lock.withLock { adapter.isTracked(deviceID: deviceID) }
  }

  public func reset() { lock.withLock { adapter = PhysicalHIDBackendEventAdapter() } }
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
/// Physical input is normalized to the internal virtual-gamepad state; the
/// profile controls the selected HID descriptor and consumer identity.
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
  public let transport: String

  /// OpenJoystickDriver virtual gamepad. This standard HID GamePad identity avoids
  /// triggering device-specific HID parsers in consumers (e.g. SDL's Xbox path).
  public static let openJoystickDriver = Self(
    vendorID: 0x4F4A,  // "OJ"
    productID: 0x4447,  // "DG" (arbitrary, stable)
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Virtual Gamepad",
    manufacturer: "OpenJoystickDriver",
    transport: "USB"
  )

  public static let openJoystickDriverGenericHID = Self(
    vendorID: 0x4F4A,
    productID: 0x4449,
    versionNumber: 0x0408,
    productName: "OpenJoystickDriver Generic HID Gamepad",
    manufacturer: "OpenJoystickDriver",
    transport: "USB"
  )

  /// Xbox One S-shaped generic-HID profile for the explicit Apple/Xbox One
  /// compatibility routes. This is not XInputHID, XUSB, or GIP emulation.
  public static let xboxOneS = Self(
    vendorID: 0x045E,
    productID: 0x02FD,
    // Important: SDL mapping DB entry for macOS expects version=0x0000 for GUID
    // `030000005e040000fd02000000000000` (Xbox One Controller, platform: Mac OS X).
    // Matching this makes SDL treat the device as a Gamepad with automatic mappings.
    versionNumber: 0x0000,
    productName: "Xbox Wireless Controller",
    manufacturer: "Microsoft",
    transport: "Bluetooth"
  )

  /// Xbox 360 Controller (Wired), experimental on macOS.
  ///
  /// Many macOS stacks do not treat 045E:028E as a standard HID gamepad.
  public static let xbox360Wired = Self(
    vendorID: 0x045E,
    productID: 0x028E,
    versionNumber: 0x0000,
    productName: "Xbox 360 Wired Controller",
    manufacturer: "Microsoft",
    transport: "USB"
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
    manufacturer: "ASTRO Gaming",
    transport: "USB"
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
