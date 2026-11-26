import Foundation

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
