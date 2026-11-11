import Foundation

/// Identifies one logical controller for profile matching and multi-controller support.
///
/// The key is the controller's hardware identity plus the address it is reached through, so
/// each interface of one physical device keys its own logical controller. The address tells
/// apart controllers whose hardware identity has no serial number; it can change when you
/// unplug and replug.
public struct LogicalControllerID: Hashable, Sendable {
  /// The model and physical identity this logical controller belongs to.
  public let hardware: ControllerHardwareIdentity
  /// Where the host reaches this logical controller, or nil when it is reached through no
  /// device address (a virtual feed).
  public let address: ControllerConnectionAddress?

  /// Creates the logical controller of `hardware` at `address`.
  public init(hardware: ControllerHardwareIdentity, address: ControllerConnectionAddress? = nil) {
    self.hardware = hardware
    self.address = address
  }

  /// Creates the logical controller of a model and serial number at an IOKit location and
  /// interface.
  ///
  /// An interface number needs a location ID.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String? = nil,
    locationID: UInt32? = nil,
    interfaceNumber: UInt8? = nil
  ) {
    precondition(locationID != nil || interfaceNumber == nil, "An interface needs a location.")
    self.init(
      hardware: ControllerHardwareIdentity(
        model: ControllerModelID(vendorID: vendorID, productID: productID),
        serialNumber: serialNumber
      ),
      address: locationID.map { .ioKit(locationID: $0, interfaceNumber: interfaceNumber) }
    )
  }

  /// The model of this logical controller, without its serial number or address.
  public var model: ControllerModelID { hardware.model }
}

extension LogicalControllerID: Comparable {
  /// Orders by model, address with no address first, then serial number, so lists of
  /// controllers come out in the same order on every run.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.model != rhs.model { return lhs.model < rhs.model }
    if lhs.address != rhs.address {
      guard let left = lhs.address else { return true }
      guard let right = rhs.address else { return false }
      return left < right
    }
    return (lhs.hardware.serialNumber ?? "") < (rhs.hardware.serialNumber ?? "")
  }
}

extension LogicalControllerID: CustomStringConvertible {
  /// Returns a human-readable representation of the logical controller for logs.
  ///
  /// It never includes the serial number, only whether one is present.
  public var description: String {
    let vid = String(format: "0x%04X", model.vendorID)
    let pid = String(format: "0x%04X", model.productID)
    let serial = hardware.serialNumber == nil ? "" : " serial=present"
    let loc = (address?.locationID).map { " loc=\($0)" } ?? ""
    let interface = address?.interfaceNumber.map { " if=\($0)" } ?? ""
    return "LogicalControllerID(VID:\(vid) PID:\(pid)\(serial)\(loc)\(interface))"
  }
}
