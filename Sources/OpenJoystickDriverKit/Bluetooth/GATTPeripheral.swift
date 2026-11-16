public import Foundation

/// One connected Bluetooth LE peripheral, as the GATT link sees it.
///
/// This is the seam over Core Bluetooth. The service implements it with a `CBPeripheral`; a test
/// implements it with a mock that records writes. Characteristics are named by UUID text.
public protocol GATTPeripheral: Sendable {
  /// The identifier Core Bluetooth gives the peripheral on this host.
  var identifier: UUID { get }
  /// Writes `bytes` to `characteristic` without response. Returns false when the peripheral is
  /// disconnected, the write is longer than the link accepts, or the characteristic is unknown.
  func writeWithoutResponse(_ bytes: [UInt8], to characteristic: String) -> Bool
}
