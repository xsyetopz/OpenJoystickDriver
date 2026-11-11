import Foundation

/// A HID connection left to macOS, with the routing address that identifies its controller.
struct PassThroughHIDDevice: Equatable {
  /// The routing address of the connection.
  let routingAddress: ControllerConnectionAddress
  /// True for a native gamepad no driver bound; false for another interface of a native one.
  let nativePassThrough: Bool
  let physicalDevice: PhysicalDevice
  /// The device as the service status reports it.
  let description: PassThroughDeviceSnapshot
}

extension DeviceManager {
  /// Observed devices left to macOS, in a stable order: native gamepads no driver bound and the
  /// other interfaces of a native controller.
  public func passThroughDeviceDescriptions() -> [PassThroughDeviceSnapshot] {
    passThroughDevices.values.map(\.description).sorted {
      ($0.vendorID, $0.productID, $0.connection) < ($1.vendorID, $1.productID, $1.connection)
    }
  }

  /// Whether a native controller holds the routing address, bound or left to macOS.
  ///
  /// Location 0 identifies no controller.
  func hasNativeHIDDevice(at address: ControllerConnectionAddress) -> Bool {
    guard address.locationID != 0 else { return false }
    return passThroughDevices.values.contains {
      $0.nativePassThrough && $0.routingAddress == address
    }
      || deviceInfos.contains { identifier, info in
        identifier.hidRoutingAddress == address && info.physicalDevice?.nativePassThrough == true
      }
  }

  // A device that reports another product name or serial number than the one recorded at its
  // location is that location's re-enumeration; interfaces of one device report alike.
  // IOKit location 0 identifies no controller.
  func retireSupersededHIDConnections(by connection: HIDDeviceConnection) async {
    let address = connection.routingAddress
    guard address.locationID != 0 else { return }
    func supersedes(_ earlier: PhysicalDevice?) -> Bool {
      guard let earlier else { return false }
      return earlier.productName != connection.physicalDevice.productName
        || earlier.serialNumber != connection.physicalDevice.serialNumber
    }
    for (id, device) in passThroughDevices
    where device.routingAddress == address && id != connection.connectionID
      && supersedes(device.physicalDevice)
    {
      clearPassThroughDevice(id)
    }
    let stale = deviceInfos.filter { identifier, info in
      guard identifier.hidRoutingAddress == address, case .hid = info.discoverySource else {
        return false
      }
      return info.hidConnectionID != connection.connectionID && supersedes(info.physicalDevice)
    }
    for identifier in stale.keys { await tearDownHIDDevice(identifier: identifier) }
  }

  /// Gives a native connection its routing address before it binds: cancels a sibling interface's
  /// initialization and tears down any other HID device OJD bound there (a sibling interface or a
  /// stale connection of the same controller), releasing its input claim, so macOS keeps every
  /// other interface of the controller.
  ///
  /// IOKit location 0 identifies no controller.
  func prepareNativeHIDLocation(_ connection: HIDDeviceConnection) async {
    let address = connection.routingAddress
    guard address.locationID != 0 else { return }
    let siblingInitializations = removeHIDInitializations(
      at: address,
      except: connection.connectionID
    )
    for initialization in siblingInitializations { initialization.task.cancel() }
    // Their orphan cleanup must finish before this connection records its own DeviceInfo, which
    // shares a sibling's identifier. This cannot deadlock: a cancelled path returns at its next
    // cancellation check, and nothing in it waits on a continuation this caller resumes.
    for initialization in siblingInitializations { await initialization.task.value }
    let siblings = deviceInfos.filter { identifier, info in
      guard identifier.hidRoutingAddress == address, case .hid = info.discoverySource else {
        return false
      }
      return info.hidConnectionID != connection.connectionID
    }
    guard !siblings.isEmpty else { return }
    // Teardown reconciles rejected siblings' claims; the bound siblings' claim is released here.
    for identifier in siblings.keys { await tearDownHIDDevice(identifier: identifier) }
    _ = await hidManager.releaseInputClaim(address: address)
  }

  /// Records a HID connection left to macOS.
  ///
  /// OJD does not bind it, so it gets no pipeline, no virtual device, and no claim reconciliation.
  func recordPassThroughDevice(
    _ connection: HIDDeviceConnection,
    vendorID: UInt16,
    productID: UInt16
  ) {
    guard !Task.isCancelled, !isStopping else { return }
    passThroughDevices[connection.connectionID] = PassThroughHIDDevice(
      routingAddress: connection.routingAddress,
      nativePassThrough: connection.physicalDevice.nativePassThrough,
      physicalDevice: connection.physicalDevice,
      description: PassThroughDeviceSnapshot(
        vendorID: vendorID,
        productID: productID,
        connection: connection.physicalDevice.transportProperty ?? "HID"
      )
    )
    notifyServiceStatusChanged()
    print(
      "[DeviceManager] HID device left to macOS (native controller):"
        + String(format: " %04x:%04x", vendorID, productID)
    )
  }

  /// Forgets the pass-through device of `connectionID`.
  func clearPassThroughDevice(_ connectionID: UUID) {
    guard passThroughDevices.removeValue(forKey: connectionID) != nil else { return }
    notifyServiceStatusChanged()
  }

  /// Forgets every pass-through device.
  func clearPassThroughDevices() {
    guard !passThroughDevices.isEmpty else { return }
    passThroughDevices.removeAll()
    notifyServiceStatusChanged()
  }
}
