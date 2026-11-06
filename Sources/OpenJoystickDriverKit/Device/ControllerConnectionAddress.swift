import Foundation

/// Where the host reaches one controller connection.
///
/// The address tells apart connections of controllers whose hardware identity has no serial
/// number, and the interfaces of one device. It can change when you unplug and replug.
public enum ControllerConnectionAddress: Hashable, Sendable {
  /// An IOKit location ID and, for a claimed USB interface or one HID role, its interface
  /// number.
  ///
  /// The location ID has the bus number in the high byte, then one port-number nibble per hub
  /// tier (`0x00130000` is bus 0, hub port 1, port 3). HID connections carry their routing
  /// location.
  case ioKit(locationID: UInt32, interfaceNumber: UInt8?)
  /// A raw USB service. The registry ID is unique only within its route, because the
  /// IOUSBHost and USBDriverKit backends can report overlapping numbers.
  case usbService(route: USBTransportRoute, serviceID: UInt64)
  /// A Bluetooth LE GATT peripheral, by the identifier Core Bluetooth gives it on this host.
  case gattPeripheral(UUID)

  /// The IOKit location ID, or nil for a USB service or GATT peripheral address.
  public var locationID: UInt32? {
    switch self {
    case .ioKit(let locationID, _): locationID
    case .usbService, .gattPeripheral: nil
    }
  }

  /// The interface number, or nil when the address names no interface.
  public var interfaceNumber: UInt8? {
    switch self {
    case .ioKit(_, let interfaceNumber): interfaceNumber
    case .usbService, .gattPeripheral: nil
    }
  }
}

extension ControllerConnectionAddress: Comparable {
  /// Orders IOKit addresses first, then USB service addresses, then GATT peripherals.
  ///
  /// IOKit addresses order by location ID, then by interface number with no interface first; USB
  /// service addresses order by route name, then registry ID; GATT peripherals order by identifier
  /// text.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (
      .ioKit(let leftLocation, let leftInterface), .ioKit(let rightLocation, let rightInterface)
    ):
      (leftLocation, leftInterface.map(Int.init) ?? -1)
        < (rightLocation, rightInterface.map(Int.init) ?? -1)
    case (.usbService(let leftRoute, let leftID), .usbService(let rightRoute, let rightID)):
      (leftRoute.rawValue, leftID) < (rightRoute.rawValue, rightID)
    case (.gattPeripheral(let left), .gattPeripheral(let right)): left.uuidString < right.uuidString
    default: lhs.rank < rhs.rank
    }
  }

  /// The position of the address kind in the ordering across kinds.
  private var rank: Int {
    switch self {
    case .ioKit: 0
    case .usbService: 1
    case .gattPeripheral: 2
    }
  }
}
