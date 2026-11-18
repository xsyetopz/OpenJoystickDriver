package import Foundation

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
///
/// Each holder, one virtual output backend, reserves the identities of its controllers. An identity
/// stays held while any holder keeps it, so a backend that replaces another for the same controller
/// publishes the same identity.
package struct VirtualIdentityRegistry: Sendable {
  /// One held identity, with the key it was derived from and the holders that keep it.
  private struct Hold {
    /// The hash input of the identity.
    let key: String
    /// The identity.
    let identity: VirtualDeviceIdentity
    /// The backends that keep the identity.
    var holders: Set<UUID>
  }

  /// The identity each connected controller holds.
  private var held: [LogicalControllerID: Hold] = [:]

  /// A registry that holds no identity.
  package init() {}

  /// The identity of `identifier` for `holder`: the one it already holds, or a new one that no
  /// other controller holds.
  package mutating func reserve(
    _ identifier: LogicalControllerID,
    holder: UUID
  ) -> VirtualDeviceIdentity {
    if let existing = held[identifier] {
      held[identifier]?.holders.insert(holder)
      return existing.identity
    }
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
    held[identifier] = Hold(key: key, identity: identity, holders: [holder])
    return identity
  }

  /// Drops `holder` from the identity of `identifier`, and frees the identity when no holder keeps
  /// it.
  package mutating func release(_ identifier: LogicalControllerID, holder: UUID) {
    held[identifier]?.holders.remove(holder)
    if held[identifier]?.holders.isEmpty == true { held.removeValue(forKey: identifier) }
  }

  /// Drops `holder` from every identity it keeps.
  package mutating func releaseAll(holder: UUID) {
    for identifier in held.keys { release(identifier, holder: holder) }
  }
}

/// One ``VirtualIdentityRegistry`` that every virtual output backend of a process shares, so two
/// controllers never publish the same identity from different backends.
package final class SharedVirtualIdentityRegistry: Sendable {
  /// The registry.
  private let registry = Locked(VirtualIdentityRegistry())

  /// A registry that holds no identity.
  package init() {}

  /// Reserves the identity of `identifier` for `holder`, as ``VirtualIdentityRegistry`` does.
  package func reserve(_ identifier: LogicalControllerID, holder: UUID) -> VirtualDeviceIdentity {
    registry.withLock { $0.reserve(identifier, holder: holder) }
  }

  /// Drops `holder` from the identity of `identifier`.
  package func release(_ identifier: LogicalControllerID, holder: UUID) {
    registry.withLock { $0.release(identifier, holder: holder) }
  }

  /// Drops `holder` from every identity it keeps.
  package func releaseAll(holder: UUID) { registry.withLock { $0.releaseAll(holder: holder) } }
}
