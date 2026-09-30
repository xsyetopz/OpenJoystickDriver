import Foundation

/// The connection lifetime that reported an unbound device.
enum UnboundDeviceKey: Hashable {
  case usb(USBTransportServiceIdentity)
  case hid(UUID)
}

/// OJD's input claim on one rejected HID connection.
struct UnboundHIDClaim: Equatable {
  let identifier: DeviceIdentifier
  let routingLocationID: UInt32
  var isReleased = false
}

extension DeviceManager {
  /// Unbound devices in a total order: identity, connection, backend, first interface number,
  /// then the connection lifetime that reported them.
  public func unboundDeviceDescriptions() -> [UnboundDeviceSnapshot] {
    func order(
      _ entry: (key: UnboundDeviceKey, value: UnboundDeviceSnapshot)
    ) -> (UInt16, UInt16, String, String, Int, String) {
      let device = entry.value
      let lifetime =
        switch entry.key {
        case .usb(let service): "usb-\(service.route)-\(service.serviceID)"
        case .hid(let connectionID): "hid-\(connectionID.uuidString)"
        }
      return (
        device.vendorID, device.productID, device.connection, device.accessBackend.rawValue,
        device.interfaces.first?.interfaceNumber.map(Int.init) ?? -1, lifetime
      )
    }
    return unboundDevices.sorted { order($0) < order($1) }.map(\.value)
  }

  func recordUnboundDevice(
    _ key: UnboundDeviceKey,
    vendorID: UInt16,
    productID: UInt16,
    connection: String,
    backend: DeviceAccessBackend,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [PhysicalInterfaceSignature]
  ) {
    unboundDevices[key] = UnboundDeviceSnapshot(
      vendorID: vendorID,
      productID: productID,
      connection: connection,
      accessBackend: backend,
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: interfaces.map(ProtocolBindingResult.InterfaceSummary.init)
    )
    notifyControllerInventoryChanged()
    print(
      "[DeviceManager] \(backend.rawValue) device left unbound:"
        + String(format: " %04x:%04x", vendorID, productID) + " reason=\(reason.rawValue)"
    )
  }

  func clearUnboundDevice(_ key: UnboundDeviceKey) {
    if case .hid(let connectionID) = key { unboundHIDClaims.removeValue(forKey: connectionID) }
    guard unboundDevices.removeValue(forKey: key) != nil else { return }
    notifyControllerInventoryChanged()
  }

  func clearUnboundHIDDevices() {
    let keys = unboundDevices.keys.filter {
      if case .hid = $0 { return true }
      return false
    }
    for key in keys { unboundDevices.removeValue(forKey: key) }
    unboundHIDClaims.removeAll()
    yieldedHIDConnections.removeAll()
    if !keys.isEmpty { notifyControllerInventoryChanged() }
  }

  /// Records a rejected HID connection and reconciles OJD's claim on it. A native controller no
  /// driver binds is left to macOS instead; OJD never claimed it.
  func rejectHIDDevice(
    _ connection: HIDDeviceConnection,
    identifier: DeviceIdentifier,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate]
  ) async {
    guard isCurrentHIDInitialization(connection) else { return }
    guard !connection.physicalDevice.nativePassThrough else {
      recordPassThroughDevice(
        connection,
        vendorID: identifier.controllerIdentity.vendorID,
        productID: identifier.controllerIdentity.productID
      )
      return
    }
    recordUnboundDevice(
      .hid(connection.connectionID),
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      connection: connection.physicalDevice.transportProperty ?? "HID",
      backend: .ioHID,
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: connection.physicalDevice.interfaces ?? []
    )
    unboundHIDClaims[connection.connectionID] = UnboundHIDClaim(
      identifier: identifier,
      routingLocationID: connection.routingLocationID
    )
    await reconcileUnboundHIDClaims()
  }

  /// Holds OJD's claim on each rejected HID connection exactly while a bound pipeline shares its
  /// physical controller or routing location, which keeps macOS from delivering duplicate input;
  /// otherwise releases it so a device no driver owns stays with macOS. An observe-only pipeline
  /// never holds a claim, since macOS keeps every interface of a native controller. Pipelines come
  /// and go independently of the rejected connection, so this runs whenever they change.
  func reconcileUnboundHIDClaims() async {
    // A pass decides from the pipelines it saw before awaiting the claim change, so another
    // pass can interleave; repeat until a pass changes nothing.
    var changed = true
    while changed {
      changed = false
      let claimingKeys = pipelines.filter { !$0.value.observesOnly }.keys
      for (connectionID, claim) in unboundHIDClaims {
        let identity = claim.identifier.controllerIdentity
        let shared = claimingKeys.contains {
          $0.locationID == claim.routingLocationID
            || identity.identifiesPhysicalDevice && $0.controllerIdentity == identity
        }
        guard shared == claim.isReleased else { continue }
        let result =
          shared
          ? await hidManager.reacquireInputClaim(locationID: claim.routingLocationID)
          : await hidManager.releaseInputClaim(locationID: claim.routingLocationID)
        guard unboundHIDClaims[connectionID] == claim else { continue }
        switch result {
        case .released, .reacquired:
          unboundHIDClaims[connectionID]?.isReleased = !shared
          changed = true
        case .unavailable: break
        case .failed:
          print(
            "[DeviceManager] HID claim reconciliation failed for loc=\(claim.routingLocationID):"
              + " \(Self.hidClaimFailureDescription(result))"
          )
        }
      }
    }
  }
}
