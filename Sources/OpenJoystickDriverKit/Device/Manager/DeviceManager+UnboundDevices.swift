import Foundation

/// The connection lifetime that reported an unbound device.
enum UnboundDeviceKey: Hashable {
  /// A raw-USB service, by its address.
  case usb(ControllerConnectionAddress)
  /// A HID connection, by its connection ID.
  case hid(UUID)
}

/// OJD's input claim on one rejected HID connection.
struct UnboundHIDClaim: Equatable {
  /// The controller identifier derived for the rejected connection.
  let identifier: LogicalControllerID
  /// The routing address of the connection, which the claim acts on.
  let routingAddress: ControllerConnectionAddress
  /// Whether OJD released the claim, so macOS delivers the device's input.
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
        case .usb(let service): "usb-\(service)"
        case .hid(let connectionID): "hid-\(connectionID.uuidString)"
        }
      return (
        device.vendorID, device.productID, device.connection, device.accessBackend.rawValue,
        device.interfaces.first?.interfaceNumber.map(Int.init) ?? -1, lifetime
      )
    }
    return unboundDevices.sorted { order($0) < order($1) }.map(\.value)
  }

  /// Records an unbound device under `key`, logs it and signals a service status change.
  func recordUnboundDevice(
    _ key: UnboundDeviceKey,
    vendorID: UInt16,
    productID: UInt16,
    productName: String?,
    connection: String,
    backend: DeviceAccessBackend,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate],
    interfaces: [PhysicalInterfaceSignature]
  ) {
    let name = productName?.trimmingCharacters(in: .whitespacesAndNewlines)
    unboundDevices[key] = UnboundDeviceSnapshot(
      vendorID: vendorID,
      productID: productID,
      name: name?.isEmpty == false ? name : nil,
      connection: connection,
      accessBackend: backend,
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: interfaces.map(ProtocolBindingResult.InterfaceSummary.init)
    )
    notifyServiceStatusChanged()
    print(
      "[DeviceManager] \(backend.rawValue) device left unbound:"
        + String(format: " %04x:%04x", vendorID, productID) + " reason=\(reason.rawValue)"
    )
  }

  /// Changes the reason of the device recorded under `key`, keeping what was observed of it.
  func replaceUnboundReason(of key: UnboundDeviceKey, with reason: ProtocolBindingReason) {
    guard let recorded = unboundDevices[key], recorded.reason != reason else { return }
    unboundDevices[key] = UnboundDeviceSnapshot(
      vendorID: recorded.vendorID,
      productID: recorded.productID,
      name: recorded.name,
      connection: recorded.connection,
      accessBackend: recorded.accessBackend,
      reason: reason,
      rejectedCandidates: recorded.rejectedCandidates,
      interfaces: recorded.interfaces
    )
    notifyServiceStatusChanged()
  }

  /// Forgets the unbound device under `key`, with the claim on it when it is a HID connection.
  func clearUnboundDevice(_ key: UnboundDeviceKey) {
    if case .hid(let connectionID) = key { unboundHIDClaims.removeValue(forKey: connectionID) }
    guard unboundDevices.removeValue(forKey: key) != nil else { return }
    notifyServiceStatusChanged()
  }

  /// Forgets every unbound HID device, the claim on each, and the HID connections yielded to raw
  /// USB.
  func clearUnboundHIDDevices() {
    let keys = unboundDevices.keys.filter {
      if case .hid = $0 { return true }
      return false
    }
    for key in keys { unboundDevices.removeValue(forKey: key) }
    unboundHIDClaims.removeAll()
    yieldedHIDConnections.removeAll()
    if !keys.isEmpty { notifyServiceStatusChanged() }
  }

  /// Records a rejected HID connection and reconciles OJD's claim on it.
  ///
  /// A native controller no driver binds is left to macOS instead; OJD never claimed it.
  func rejectHIDDevice(
    _ connection: HIDDeviceConnection,
    identifier: LogicalControllerID,
    reason: ProtocolBindingReason,
    rejectedCandidates: [ProtocolBindingResult.RejectedCandidate]
  ) async {
    guard isCurrentHIDInitialization(connection) else { return }
    guard !connection.physicalDevice.nativePassThrough else {
      recordPassThroughDevice(
        connection,
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID
      )
      return
    }
    recordUnboundDevice(
      .hid(connection.connectionID),
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      productName: connection.physicalDevice.productName,
      connection: connection.physicalDevice.transportProperty ?? "HID",
      backend: connection.accessBackend,
      reason: reason,
      rejectedCandidates: rejectedCandidates,
      interfaces: connection.physicalDevice.interfaces ?? []
    )
    unboundHIDClaims[connection.connectionID] = UnboundHIDClaim(
      identifier: identifier,
      routingAddress: connection.routingAddress
    )
    await reconcileUnboundHIDClaims()
  }

  /// Holds OJD's claim on each rejected HID connection exactly while a bound pipeline shares its
  /// physical controller or routing location, which keeps macOS from delivering duplicate input;
  /// otherwise releases it so a device no driver owns stays with macOS.
  ///
  /// An observe-only pipeline never holds a claim, since macOS keeps every interface of a native
  /// controller. Pipelines come and go independently of the rejected connection, so this runs
  /// whenever they change.
  func reconcileUnboundHIDClaims() async {
    // A pass decides from the pipelines it saw before awaiting the claim change, so another
    // pass can interleave; repeat until a pass changes nothing.
    var changed = true
    while changed {
      changed = false
      let claimingKeys = pipelines.filter { !$0.value.observesOnly }.keys
      for (connectionID, claim) in unboundHIDClaims {
        let identity = claim.identifier.hardware
        let shared = claimingKeys.contains {
          $0.hidRoutingAddress == claim.routingAddress
            || identity.identifiesPhysicalDevice && $0.hardware == identity
        }
        guard shared == claim.isReleased else { continue }
        let result =
          shared
          ? await hidManager.reacquireInputClaim(address: claim.routingAddress)
          : await hidManager.releaseInputClaim(address: claim.routingAddress)
        guard unboundHIDClaims[connectionID] == claim else { continue }
        switch result {
        case .released, .reacquired:
          unboundHIDClaims[connectionID]?.isReleased = !shared
          changed = true
        case .unavailable: break
        case .failed:
          print(
            "[DeviceManager] HID claim reconciliation failed for route=\(claim.routingAddress):"
              + " \(Self.hidClaimFailureDescription(result))"
          )
        }
      }
    }
  }
}
