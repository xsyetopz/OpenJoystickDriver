import Foundation

/// How discovery keys and runs one HID connection.
enum HIDConnectionRole: Equatable {
  /// The connection is its location's controller. Every family without a HID role predicate
  /// runs this way: one controller per routing location, keyed with no interface.
  case location
  /// The connection is one protocol role of its device, keyed with its USB interface number.
  case interface(UInt8)
  /// The connection belongs to a family that declares HID roles but is not one of them.
  case notARole
}

extension ProtocolDriverRegistry {
  /// Exact catalog models whose family declares HID roles. The HID backend reports each
  /// connection of these models as disconnected on its own, not only once its location empties.
  public var hidRoleIdentifiers: [DeviceIdentifier] {
    hidIdentifiers.filter { record(for: $0).map(Self.declaresHIDRoles) == true }
  }

  /// The role one observed HID connection plays.
  ///
  /// Only `valve.steam-controller` declares a role predicate, pinned to Linux `hid-steam.c` at
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
  /// (`triton` quirk) dongles carry controllers on interfaces 2–5 only (SDL
  /// `SDL_hidapi_steam_triton.c`).
  func hidConnectionRole(of device: PhysicalDevice) -> HIDConnectionRole {
    guard let record = hidRoleRecord(of: device) else { return .location }
    guard let interface = device.interfaces?.first, device.interfaces?.count == 1,
      let descriptor = interface.hidLayout?.reportDescriptor,
      HIDReportDescriptorParser.parse(descriptor: Array(descriptor))?.containsFeatureItem == true
    else { return .notARole }
    let isTriton = record.quirks.contains(.triton)
    guard let interfaceNumber = interface.interfaceNumber else {
      return interface.hostTransport == .bluetoothLE ? .location : .notARole
    }
    if isTriton, record.physicalProtocolVariant == .dongle, !(2...5).contains(interfaceNumber) {
      return .notARole
    }
    return .interface(interfaceNumber)
  }

  /// Whether the device's catalog family declares HID roles, whether or not this connection is
  /// one of them.
  func declaresHIDRoles(_ device: PhysicalDevice) -> Bool { hidRoleRecord(of: device) != nil }

  private func hidRoleRecord(of device: PhysicalDevice) -> DeviceRuntimeProfile? {
    guard let vendorID = device.vendorID, let productID = device.productID,
      let record = record(for: DeviceIdentifier(vendorID: vendorID, productID: productID)),
      Self.declaresHIDRoles(record)
    else { return nil }
    return record
  }

  /// The driver-owned assembly policy a binding's catalog row names.
  ///
  /// Nil means each protocol role is its own logical controller. The policy vocabulary is empty
  /// (``ControllerAssemblyPolicy``), so today this is nil for every row: discovery consumes the
  /// selection, and no row can produce one until a row with multi-interface evidence adds the
  /// first policy.
  func assemblyPolicy(for binding: ProtocolBinding) -> ControllerAssemblyPolicy? {
    binding.record?.assemblyPolicy
  }

  private static func declaresHIDRoles(_ record: DeviceRuntimeProfile) -> Bool {
    record.physicalProtocolID == .valveSteamController
  }
}
