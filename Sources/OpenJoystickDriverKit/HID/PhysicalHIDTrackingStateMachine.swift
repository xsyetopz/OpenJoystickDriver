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
  /// Virtual HID profiles intentionally spoof third-party product names, transports, and
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
  fileprivate static func serialNumber(forKey key: String) -> String {
    serialPrefix + hex64(fnv1a64(key))
  }

  /// The virtual LocationID hashed from `key`.
  fileprivate static func locationID(forKey key: String) -> UInt32 {
    let low16 = UInt32(truncatingIfNeeded: fnv1a64(key) & 0xFFFF)
    // Avoid 0/1 because some consumers treat these as special/invalid.
    let safeLow16 = (low16 <= 1) ? (low16 &+ 2) : low16
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | safeLow16
  }

  /// The LocationID after `locationID`, wrapping within the 16 low bits and skipping 0 and 1.
  fileprivate static func nextLocationID(after locationID: UInt32) -> UInt32 {
    let next = (locationID &+ 1) & 0xFFFF
    return VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace | (next <= 1 ? 2 : next)
  }

  // MARK: - Private helpers

  /// The text that the hash of a virtual device's identity is taken from.
  ///
  /// It joins the vendor ID, the product ID, the serial number, the location ID (only without a
  /// serial number, or when `includingLocation`) and the interface number.
  fileprivate static func stableKey(
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

/// The serial number and LocationID that one virtual device publishes.
package struct VirtualDeviceIdentity: Sendable, Equatable {
  /// The virtual serial number.
  package let serialNumber: String
  /// The virtual LocationID in the OJD namespace.
  package let locationID: UInt32
}

/// The identities of the connected virtual devices; it gives each controller a serial number and a
/// LocationID that no other connected controller holds.
///
/// The first controller of a VID:PID:serial key keeps the plain key. A later controller with the
/// same key adds its location to the key.
package struct VirtualIdentityRegistry: Sendable {
  /// The key and identity each connected controller holds.
  private var held: [LogicalControllerID: (key: String, identity: VirtualDeviceIdentity)] = [:]

  /// A registry that holds no identity.
  package init() {}

  /// The identity of `identifier`, the one it already holds or a new one that no other controller
  /// holds.
  package mutating func reserve(_ identifier: LogicalControllerID) -> VirtualDeviceIdentity {
    if let existing = held[identifier] { return existing.identity }
    let plainKey = UserSpaceVirtualDeviceConstants.stableKey(for: identifier)
    let keyIsHeld = held.values.contains { $0.key == plainKey }
    let key =
      keyIsHeld
      ? UserSpaceVirtualDeviceConstants.stableKey(for: identifier, includingLocation: true)
      : plainKey
    var locationID = UserSpaceVirtualDeviceConstants.locationID(forKey: key)
    while held.values.contains(where: { $0.identity.locationID == locationID }) {
      locationID = UserSpaceVirtualDeviceConstants.nextLocationID(after: locationID)
    }
    let identity = VirtualDeviceIdentity(
      serialNumber: UserSpaceVirtualDeviceConstants.serialNumber(forKey: key),
      locationID: locationID
    )
    held[identifier] = (key, identity)
    return identity
  }

  /// Frees the identity of `identifier`.
  package mutating func release(_ identifier: LogicalControllerID) {
    held.removeValue(forKey: identifier)
  }
}

/// Minimal state machine shared by HID backend adapters for physical-device ownership.
public enum PhysicalHIDBackendEventPolicy {
  /// Whether the backend may admit a device; it applies
  /// `UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDDevice`.
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

  /// Whether the backend may process `event`; it applies
  /// `UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent`.
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

/// Tracks the physical HID devices that a backend admits, with the ownership of each location.
public struct PhysicalHIDTrackingStateMachine {
  /// One tracked device.
  private struct Device {
    /// The location ID the device reports.
    let locationID: UInt32
    /// The IORegistry entry ID of the backing service; nil when unknown.
    let serviceID: UInt64?
    /// Whether macOS keeps serving the device, so OJD never seizes it.
    let nativePassThrough: Bool
    /// Whether removing the device disconnects it even when other devices stay at its location.
    var disconnectsIndividually: Bool
    let enumerationKey: String?
    /// The observed ownership of the device.
    var ownership: HIDInputOwnership
  }

  /// The tracked devices by device ID.
  private var devices: [UInt64: Device] = [:]
  /// The IDs of the devices that OJD may seize, by location ID.
  private var deviceIDsByLocation: [UInt32: Set<UInt64>] = [:]
  /// The device ID of the first device admitted for each service ID.
  private var deviceIDsByService: [UInt64: UInt64] = [:]
  /// Native devices by shared routing location; location 0 identifies no controller.
  private var nativeDeviceIDsByLocation: [UInt32: Set<UInt64>] = [:]

  /// Creates a state machine that tracks no device.
  public init() {}

  /// Registers one device object. `serviceID` is the IORegistry entry ID of the backing service:
  /// IOHIDManager creates a separate device object for each matching dictionary a service
  /// satisfies, so only the first object per service is admitted.
  ///
  /// A native pass-through device is never seized, so it stays out of its location's ownership
  /// and disconnect state. A device that `disconnectsIndividually` (an interface of a family with
  /// HID protocol roles) shares its location's ownership but disconnects on its own removal.
  ///
  /// A device whose `enumerationKey` differs from the key of a device already at its location is
  /// that device's successor after a re-enumeration; the earlier device then disconnects on its
  /// own removal too, whichever of the two events comes first. Devices with the same key, or
  /// without one, are interfaces of one device.
  @discardableResult
  public mutating func register(
    deviceID: UInt64,
    locationID: UInt32,
    syntheticProperty: Any?,
    ownership: HIDInputOwnership = .unknown,
    serviceID: UInt64? = nil,
    nativePassThrough: Bool = false,
    disconnectsIndividually: Bool = false,
    enumerationKey: String? = nil
  ) -> Bool {
    guard PhysicalHIDBackendEventPolicy.accepts(.deviceAdded, syntheticProperty: syntheticProperty),
      devices[deviceID] == nil
    else { return false }
    if let serviceID {
      guard deviceIDsByService[serviceID] == nil else { return false }
      deviceIDsByService[serviceID] = deviceID
    }
    devices[deviceID] = Device(
      locationID: locationID,
      serviceID: serviceID,
      nativePassThrough: nativePassThrough,
      disconnectsIndividually: disconnectsIndividually,
      enumerationKey: enumerationKey,
      ownership: ownership
    )
    if !nativePassThrough {
      if let enumerationKey {
        for earlierID in deviceIDsByLocation[locationID] ?? [] {
          guard let earlierKey = devices[earlierID]?.enumerationKey, earlierKey != enumerationKey
          else { continue }
          devices[earlierID]?.disconnectsIndividually = true
        }
      }
      deviceIDsByLocation[locationID, default: []].insert(deviceID)
    } else if locationID != 0 {
      nativeDeviceIDsByLocation[locationID, default: []].insert(deviceID)
    }
    return true
  }

  /// Whether a native pass-through device holds the location; macOS keeps the other interfaces of
  /// that location.
  public func hasNativeDevice(locationID: UInt32) -> Bool {
    nativeDeviceIDsByLocation[locationID] != nil
  }

  /// A native device's location routes only that device's input: a sibling interface of the same
  /// controller is left to macOS.
  public func acceptsInput(deviceID: UInt64) -> Bool {
    guard let device = devices[deviceID] else { return false }
    if !device.nativePassThrough, hasNativeDevice(locationID: device.locationID) { return false }
    return device.ownership != .ownedByAnotherClient
  }

  /// Whether the device is tracked.
  public func isTracked(deviceID: UInt64) -> Bool { devices[deviceID] != nil }

  /// Whether any device at the location accepts input.
  public func acceptsInput(locationID: UInt32) -> Bool {
    (deviceIDsByLocation[locationID] ?? []).contains { acceptsInput(deviceID: $0) }
  }

  /// The ownership of the device; nil when it is not tracked.
  public func ownership(deviceID: UInt64) -> HIDInputOwnership? { devices[deviceID]?.ownership }

  /// The combined ownership of the devices at the location, the least favorable one among them;
  /// `unknown` when none is tracked.
  public func ownership(locationID: UInt32) -> HIDInputOwnership {
    HIDInputOwnership.combined(
      (deviceIDsByLocation[locationID] ?? []).compactMap { devices[$0]?.ownership }
    )
  }

  /// Sets the ownership of the device; returns false when the device is not tracked.
  @discardableResult
  public mutating func updateOwnership(_ ownership: HIDInputOwnership, deviceID: UInt64) -> Bool {
    guard devices[deviceID] != nil else { return false }
    devices[deviceID]?.ownership = ownership
    return true
  }

  /// Whether feedback to the location may reach a device; the answer is the one for input.
  public func acceptsFeedback(locationID: UInt32) -> Bool { acceptsInput(locationID: locationID) }

  /// Whether removing this device disconnects it while other devices stay tracked at its
  /// location: a device that disconnects individually and has siblings.
  public func disconnectsBeforeItsLocation(deviceID: UInt64) -> Bool {
    guard let device = devices[deviceID], device.disconnectsIndividually else { return false }
    return deviceIDsByLocation[device.locationID]?.contains { $0 != deviceID } == true
  }

  /// Removes one device and returns true when it disconnects.
  ///
  /// A native pass-through device and a device that disconnects individually always disconnect; any
  /// other device disconnects when its removal leaves its location empty.
  @discardableResult
  public mutating func remove(deviceID: UInt64) -> Bool {
    guard let device = devices.removeValue(forKey: deviceID) else { return false }
    let locationID = device.locationID
    if let serviceID = device.serviceID { deviceIDsByService.removeValue(forKey: serviceID) }
    guard !device.nativePassThrough else {
      nativeDeviceIDsByLocation[locationID]?.remove(deviceID)
      if nativeDeviceIDsByLocation[locationID]?.isEmpty == true {
        nativeDeviceIDsByLocation.removeValue(forKey: locationID)
      }
      return true
    }
    deviceIDsByLocation[locationID]?.remove(deviceID)
    guard deviceIDsByLocation[locationID]?.isEmpty == true else {
      return device.disconnectsIndividually
    }
    deviceIDsByLocation.removeValue(forKey: locationID)
    return true
  }

  /// Removes all devices at a location and returns whether a tracked location existed.
  @discardableResult
  public mutating func remove(locationID: UInt32) -> Bool {
    guard let deviceIDs = deviceIDsByLocation.removeValue(forKey: locationID), !deviceIDs.isEmpty
    else { return false }
    for deviceID in deviceIDs {
      if let serviceID = devices.removeValue(forKey: deviceID)?.serviceID {
        deviceIDsByService.removeValue(forKey: serviceID)
      }
    }
    return true
  }
}

/// Applies the admission and tracking rules for one HID backend.
public struct PhysicalHIDBackendEventAdapter {
  /// What a removal changed.
  public struct RemovalDecision: Equatable, Sendable {
    /// Whether the device was tracked.
    public let wasTracked: Bool
    /// Whether the removal ended the device's whole location.
    public let locationRemoved: Bool
    /// Whether the backend should cancel its notification for the device; true for every tracked
    /// device.
    public let shouldCancelNotification: Bool
    /// Whether the backend should report a disconnect.
    public let shouldEmitDisconnect: Bool

    /// Creates a decision from its fields.
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

  /// The tracked devices.
  private var tracking = PhysicalHIDTrackingStateMachine()

  /// Creates an adapter that tracks no device.
  public init() {}

  /// Admits a device unless it is synthetic or already tracked; returns whether it was admitted.
  ///
  /// The rules are those of `PhysicalHIDTrackingStateMachine.register`.
  @discardableResult
  public mutating func add(
    deviceID: UInt64,
    locationID: UInt32,
    syntheticProperty: Any?,
    ownership: HIDInputOwnership = .unknown,
    serviceID: UInt64? = nil,
    nativePassThrough: Bool = false,
    disconnectsIndividually: Bool = false,
    enumerationKey: String? = nil
  ) -> Bool {
    tracking.register(
      deviceID: deviceID,
      locationID: locationID,
      syntheticProperty: syntheticProperty,
      ownership: ownership,
      serviceID: serviceID,
      nativePassThrough: nativePassThrough,
      disconnectsIndividually: disconnectsIndividually,
      enumerationKey: enumerationKey
    )
  }

  /// The ownership of the device; nil when it is not tracked.
  public func ownership(deviceID: UInt64) -> HIDInputOwnership? {
    tracking.ownership(deviceID: deviceID)
  }

  /// The combined ownership of the devices at the location.
  public func ownership(locationID: UInt32) -> HIDInputOwnership {
    tracking.ownership(locationID: locationID)
  }

  /// Whether a native pass-through device holds the location.
  public func hasNativeDevice(locationID: UInt32) -> Bool {
    tracking.hasNativeDevice(locationID: locationID)
  }

  /// Sets the ownership of the device; returns false when the device is not tracked.
  @discardableResult
  public mutating func updateOwnership(_ ownership: HIDInputOwnership, deviceID: UInt64) -> Bool {
    tracking.updateOwnership(ownership, deviceID: deviceID)
  }

  /// Whether input from the device is accepted.
  public func acceptsInput(deviceID: UInt64) -> Bool { tracking.acceptsInput(deviceID: deviceID) }

  /// Whether feedback to the location may reach a device.
  public func acceptsFeedback(locationID: UInt32) -> Bool {
    tracking.acceptsFeedback(locationID: locationID)
  }

  /// Whether the backend may read the descriptor of a device with `syntheticProperty`; false for
  /// Apple's synthetic device.
  public func acceptsDescriptor(syntheticProperty: Any?) -> Bool {
    PhysicalHIDBackendEventPolicy.accepts(
      .descriptorDiscovery,
      syntheticProperty: syntheticProperty
    )
  }

  /// Removes the device and says what the removal changed.
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
    let siblingsRemain = tracking.disconnectsBeforeItsLocation(deviceID: deviceID)
    let disconnects = tracking.remove(deviceID: deviceID)
    return RemovalDecision(
      wasTracked: true,
      locationRemoved: disconnects && !siblingsRemain,
      shouldCancelNotification: true,
      shouldEmitDisconnect: disconnects
    )
  }

  /// Whether the device is tracked.
  public func isTracked(deviceID: UInt64) -> Bool { tracking.isTracked(deviceID: deviceID) }
}

/// Thread-safe holder for backend callbacks and feedback callers that may run on different queues.
///
/// The holder lock is never held while a backend lock is acquired, so callers can safely compose
/// it with framework/device locks.
public final class SynchronizedPhysicalHIDBackendEventAdapter: @unchecked Sendable {
  /// Guards `adapter`.
  private let lock = NSLock()
  /// The adapter that the lock guards.
  private var adapter = PhysicalHIDBackendEventAdapter()

  /// Creates an adapter that tracks no device.
  public init() {}

  /// Admits a device unless it is synthetic or already tracked; returns whether it was admitted.
  @discardableResult
  public func add(
    deviceID: UInt64,
    locationID: UInt32,
    syntheticProperty: Any?,
    ownership: HIDInputOwnership = .unknown,
    serviceID: UInt64? = nil,
    nativePassThrough: Bool = false,
    disconnectsIndividually: Bool = false,
    enumerationKey: String? = nil
  ) -> Bool {
    lock.withLock {
      adapter.add(
        deviceID: deviceID,
        locationID: locationID,
        syntheticProperty: syntheticProperty,
        ownership: ownership,
        serviceID: serviceID,
        nativePassThrough: nativePassThrough,
        disconnectsIndividually: disconnectsIndividually,
        enumerationKey: enumerationKey
      )
    }
  }

  /// The ownership of the device; nil when it is not tracked.
  public func ownership(deviceID: UInt64) -> HIDInputOwnership? {
    lock.withLock { adapter.ownership(deviceID: deviceID) }
  }

  /// The combined ownership of the devices at the location.
  public func ownership(locationID: UInt32) -> HIDInputOwnership {
    lock.withLock { adapter.ownership(locationID: locationID) }
  }

  /// Whether a native pass-through device holds the location.
  public func hasNativeDevice(locationID: UInt32) -> Bool {
    lock.withLock { adapter.hasNativeDevice(locationID: locationID) }
  }

  /// Sets the ownership of the device; returns false when the device is not tracked.
  @discardableResult
  public func updateOwnership(_ ownership: HIDInputOwnership, deviceID: UInt64) -> Bool {
    lock.withLock { adapter.updateOwnership(ownership, deviceID: deviceID) }
  }

  /// Whether input from the device is accepted.
  public func acceptsInput(deviceID: UInt64) -> Bool {
    lock.withLock { adapter.acceptsInput(deviceID: deviceID) }
  }

  /// Whether feedback to the location may reach a device.
  public func acceptsFeedback(locationID: UInt32) -> Bool {
    lock.withLock { adapter.acceptsFeedback(locationID: locationID) }
  }

  /// Whether the backend may read the descriptor of a device with `syntheticProperty`.
  public func acceptsDescriptor(syntheticProperty: Any?) -> Bool {
    lock.withLock { adapter.acceptsDescriptor(syntheticProperty: syntheticProperty) }
  }

  /// Removes the device and says what the removal changed.
  public func remove(deviceID: UInt64) -> PhysicalHIDBackendEventAdapter.RemovalDecision {
    lock.withLock { adapter.remove(deviceID: deviceID) }
  }

  /// Whether the device is tracked.
  public func isTracked(deviceID: UInt64) -> Bool {
    lock.withLock { adapter.isTracked(deviceID: deviceID) }
  }

  /// Forgets every tracked device.
  public func reset() { lock.withLock { adapter = PhysicalHIDBackendEventAdapter() } }
}
