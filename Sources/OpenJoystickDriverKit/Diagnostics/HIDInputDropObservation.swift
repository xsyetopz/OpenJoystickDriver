/// One HID client's count of input reports the system dropped because the queue between the
/// device and the client was full.
package struct HIDInputDropObservation: Equatable, Sendable {
  /// The name of the product the client reads.
  package let productName: String
  /// The USB vendor ID of the product.
  package let vendorID: Int
  /// The USB product ID of the product.
  package let productID: Int
  /// The number of reports dropped.
  package let droppedReports: Int

  /// Creates an observation from its values.
  package init(productName: String, vendorID: Int, productID: Int, droppedReports: Int) {
    self.productName = productName
    self.vendorID = vendorID
    self.productID = productID
    self.droppedReports = droppedReports
  }
}
