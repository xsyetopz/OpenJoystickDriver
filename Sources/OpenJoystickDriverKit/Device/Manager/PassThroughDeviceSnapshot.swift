/// A HID device OJD left to macOS.
public struct PassThroughDeviceSnapshot: Equatable, Sendable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The connection label, such as "USB" or the HID transport property.
  public let connection: String

  /// Creates a snapshot of a HID device left to macOS.
  public init(vendorID: UInt16, productID: UInt16, connection: String) {
    self.vendorID = vendorID
    self.productID = productID
    self.connection = connection
  }
}
