import Foundation

/// The key one pending HID initialization runs under.
///
/// A connection of a family with HID protocol roles owns its key, so a sibling interface's arrival
/// never cancels it. Every other connection shares its routing address's key, and a later
/// connection there replaces the earlier one.
enum HIDInitializationKey: Hashable {
  /// The key shared by every connection at one routing address.
  case address(ControllerConnectionAddress)
  /// The key that one connection owns.
  case connection(UUID)
}

extension DeviceManager {
  /// The key `connection` initializes under: its own for a family with HID protocol roles, its
  /// routing address's otherwise.
  func hidInitializationKey(for connection: HIDDeviceConnection) -> HIDInitializationKey {
    protocolDriverRegistry.declaresHIDRoles(connection.physicalDevice)
      ? .connection(connection.connectionID) : .address(connection.routingAddress)
  }

  /// The initialization key of a bound HID controller.
  ///
  /// A HID key carries an interface number only for a protocol role.
  func hidInitializationKey(
    for identifier: LogicalControllerID,
    connectionID: UUID
  ) -> HIDInitializationKey? {
    if identifier.address?.interfaceNumber != nil { return .connection(connectionID) }
    return identifier.hidRoutingAddress.map(HIDInitializationKey.address)
  }

  /// Removes every pending initialization at a routing address except that of `connectionID`.
  ///
  /// The caller cancels the returned initializations.
  func removeHIDInitializations(
    at address: ControllerConnectionAddress,
    except connectionID: UUID? = nil
  ) -> [HIDDeviceInitialization] {
    let keys = hidInitializationTasks.filter {
      $0.value.connection.routingAddress == address
        && $0.value.connection.connectionID != connectionID
    }.keys
    return keys.compactMap { hidInitializationTasks.removeValue(forKey: $0) }
  }

  /// The logical-controller key of a HID connection: its routing address's controller, or one role
  /// keyed with its location and interface number.
  ///
  /// Nil without an observed vendor and product ID.
  func hidIdentifier(
    for connection: HIDDeviceConnection,
    role: HIDConnectionRole
  ) -> LogicalControllerID? {
    let physicalDevice = connection.physicalDevice
    guard let vendorID = physicalDevice.vendorID, let productID = physicalDevice.productID else {
      return nil
    }
    var address = connection.routingAddress
    if case .interface(let number) = role, let locationID = address.locationID {
      address = .ioKit(locationID: locationID, interfaceNumber: number)
    }
    return LogicalControllerID(
      hardware: ControllerHardwareIdentity(
        model: ControllerModelID(vendorID: vendorID, productID: productID),
        serialNumber: physicalDevice.serialNumber
      ),
      address: address
    )
  }

  /// The pipeline that input from one HID connection feeds.
  ///
  /// A protocol role receives only its own connection's input. Any other connection feeds its
  /// location's controller, but never a role: a family's non-role interface carries no controller
  /// input. Only a role's HID key carries an interface number.
  ///
  /// Routing is per connection, but ownership is not: a location's seize, its release to another
  /// client and its reacquisition act on every interface there, so seizing or releasing one role's
  /// interface affects its sibling roles too.
  /// role's interface affects its sibling roles too.
  func hidPipelineKey(
    forInputFrom connectionID: UUID,
    address: ControllerConnectionAddress
  ) -> LogicalControllerID? {
    if let identifier = hidRoleConnections[connectionID] {
      return deviceInfos[identifier]?.hidConnectionID == connectionID ? identifier : nil
    }
    return pipelines.keys.first { $0.address == address }
  }

  /// Whether a HID controller's output must target its exact connection.
  ///
  /// A native controller is never seized, and a protocol role shares its location with sibling
  /// interfaces, so the location path reaches neither.
  func writesExactHIDConnection(_ identifier: LogicalControllerID, pipeline: DevicePipeline) -> Bool
  {
    pipeline.observesOnly || identifier.address?.interfaceNumber != nil
  }

  /// The connection a bound HID controller was admitted on.
  func currentHIDConnection(
    for identifier: LogicalControllerID,
    address: ControllerConnectionAddress
  ) -> HIDDeviceConnection? {
    guard let info = deviceInfos[identifier], let connectionID = info.hidConnectionID,
      let physicalDevice = info.physicalDevice
    else { return nil }
    return HIDDeviceConnection(
      connectionID: connectionID,
      physicalDevice: physicalDevice,
      routingAddress: address
    )
  }
}

extension LogicalControllerID {
  /// The routing address of a HID controller: its address without a protocol role's interface
  /// number.
  var hidRoutingAddress: ControllerConnectionAddress? {
    guard let address else { return nil }
    guard let locationID = address.locationID else { return address }
    return .ioKit(locationID: locationID, interfaceNumber: nil)
  }
}
