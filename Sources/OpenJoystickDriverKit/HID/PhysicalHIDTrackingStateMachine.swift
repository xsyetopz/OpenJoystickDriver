import Foundation

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
