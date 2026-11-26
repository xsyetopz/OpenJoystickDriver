import Foundation

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
