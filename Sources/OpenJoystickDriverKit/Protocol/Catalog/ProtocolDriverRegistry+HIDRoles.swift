import Foundation

/// How discovery keys and runs one HID connection.
enum HIDConnectionRole: Equatable {
  /// The connection is its location's controller. Every family without a HID role predicate
  /// runs this way: one controller per routing location, keyed with no interface.
  case location
  /// The connection is one protocol role of its device, keyed with its USB interface number.
  case interface(UInt8)
  /// The connection belongs to a family that declares HID roles but is not one of them.
  case notRole
}

extension ProtocolDriverRegistry {
  /// Exact catalog models whose family declares HID roles.
  ///
  /// The HID backend reports each connection of these models as disconnected on its own, not only
  /// once its location empties.
  public var hidRoleModels: [ControllerModelID] {
    hidModels.filter { record(for: $0).map(Self.declaresHIDRoles) == true }
  }

  /// The role one observed HID connection plays.
  ///
  /// Only `ValveSteamController` declares a role predicate, pinned to Linux `hid-steam.c` at
  /// the locked commit: `steam_is_valve_interface` (hid-steam.c:1095–1111) treats an interface
  /// as a real gamepad exactly when its report descriptor declares a feature report. The wired
  /// controller exposes mouse 0, keyboard 1 and gamepad 2; the wireless dongle exposes keyboard
  /// 0 and slots 1–4. `steam_probe` leaves the other interfaces to the input stack
  /// (hid-steam.c:1226–1231). A qualifying interface without an observed USB interface number
  /// cannot be told apart from its siblings, so it fails closed as not a role.
  ///
  /// A Bluetooth LE link has one HID service and no USB interface number, so that connection is
  /// its location's controller; SDL `HIDAPI_DriverSteam_IsSupportedDevice` and
  /// `HIDAPI_DriverSteamTriton_IsSupportedDevice` accept every Bluetooth interface. The Triton
  /// (`ValveSteamTriton`) dongles carry controllers on interfaces 2–5 only (SDL
  /// `SDL_hidapi_steam_triton.c`).
  func hidConnectionRole(of device: PhysicalDevice) -> HIDConnectionRole {
    guard let record = hidRoleRecord(of: device) else { return .location }
    guard let interface = device.interfaces?.first, device.interfaces?.count == 1,
      let descriptor = interface.hidLayout?.reportDescriptor,
      HIDReportDescriptorParser.parse(descriptor: Array(descriptor))?.containsFeatureItem == true
    else { return .notRole }
    guard let interfaceNumber = interface.interfaceNumber else {
      return interface.hostTransport == .bluetoothLE ? .location : .notRole
    }
    if record.physicalProtocolID == .valveSteamTriton, record.physicalProtocolVariant == .dongle,
      !(2...5).contains(interfaceNumber)
    {
      return .notRole
    }
    return .interface(interfaceNumber)
  }

  /// Whether the device's catalog family declares HID roles, whether or not this connection is
  /// one of them.
  func declaresHIDRoles(_ device: PhysicalDevice) -> Bool { hidRoleRecord(of: device) != nil }

  /// The catalog record of `device` when its family declares HID roles; nil otherwise.
  private func hidRoleRecord(of device: PhysicalDevice) -> DeviceRuntimeProfile? {
    guard let vendorID = device.vendorID, let productID = device.productID,
      let record = record(for: ControllerModelID(vendorID: vendorID, productID: productID)),
      Self.declaresHIDRoles(record)
    else { return nil }
    return record
  }

  /// The driver-owned assembly policy that a binding's catalog row names.
  ///
  /// Nil means each protocol role is its own logical controller. ``ControllerAssemblyPolicy`` has
  /// no cases, so no catalog row names a policy and the result is always nil.
  func assemblyPolicy(for binding: ProtocolBinding) -> ControllerAssemblyPolicy? {
    binding.record?.assemblyPolicy
  }

  /// Whether the family of `record` is one of the Valve families that declare HID roles.
  private static func declaresHIDRoles(_ record: DeviceRuntimeProfile) -> Bool {
    [.valveSteamController, .valveSteamTriton, .valveSteamDeck].contains(record.physicalProtocolID)
  }
}
