import Foundation

/// The model of a controller: its vendor ID and product ID, and nothing that tells units apart.
///
/// Every physical unit of one model has the same model ID, whatever its serial number or the
/// location, interface or link it is reached through. A controller record describes one model,
/// so the model ID is the key that finds a record.
public struct ControllerModelID: Hashable, Comparable, Sendable {
  /// Vendor ID (VID): who made the controller (e.g. 0x3537 = GameSir).
  public let vendorID: UInt16
  /// Product ID (PID): which of the vendor's models it is (e.g. 0x1010 = G7 SE).
  public let productID: UInt16

  /// Creates the model ID for a vendor ID and product ID.
  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  /// The model for the vendor ID and product ID a HID API reports, or nil when either is
  /// missing or does not fit in 16 bits.
  package init?(vendorID: UInt64?, productID: UInt64?) {
    guard let vendorID, let productID, let representableVendorID = UInt16(exactly: vendorID),
      let representableProductID = UInt16(exactly: productID)
    else { return nil }
    self.init(vendorID: representableVendorID, productID: representableProductID)
  }

  /// Orders by vendor ID, then product ID.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.vendorID, lhs.productID) < (rhs.vendorID, rhs.productID)
  }
}

extension ControllerModelID: CustomStringConvertible {
  /// The vendor and product ID as four uppercase hex digits each, such as `045E:02EA`.
  public var description: String { String(format: "%04X:%04X", vendorID, productID) }
}

extension PhysicalDevice {
  /// The model of this device, or nil when it reports no vendor ID or product ID.
  public var model: ControllerModelID? {
    guard let vendorID, let productID else { return nil }
    return ControllerModelID(vendorID: vendorID, productID: productID)
  }
}
